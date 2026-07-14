// Schedule-fallback logic (Phase 1 — the stop arrivals list). Pure and
// testable: resolve the active GTFS service(s) for a date, pick the upcoming
// planned departures at a stop, and dedup them against the live board so the
// list reads "live first + schedule tail" (like the competitors) rather than
// doubling a bus that already has a live vehicle.

export interface ScheduleMeta {
  unit: "minutes";
  services: Record<string, Record<string, number>>; // service_id -> {monday..sunday: 0|1}
  exceptions: Record<string, { add: string[]; remove: string[] }>; // ISO date -> adds/removes
  dow: string[]; // ["sunday","monday",...]
}

// One line/direction's planned departures at a stop, minutes since midnight
// (values >=1440 are overnight, i.e. the small hours of the next calendar day).
export interface StopScheduleEntry {
  line: string;
  route_id: string; // direction-specific bundle key (matches live direction_route_id)
  dir: string;
  svc: Record<string, number[]>; // service_id -> sorted minutes
}
export interface StopSchedule {
  stop_id: string;
  deps: StopScheduleEntry[];
}

export interface ScheduledArrival {
  line: string;
  route_id: string;
  dir: string;
  eta_minutes: number;
}

// Belgrade wall-clock context for "now", derived in the Europe/Belgrade zone so
// schedule minutes (local) line up regardless of the Worker's UTC clock.
export interface NowContext {
  dateISO: string; // today, YYYY-MM-DD (Belgrade)
  yesterdayISO: string; // for overnight trips spilling past midnight
  minutes: number; // minutes since local midnight
}

const TZ = "Europe/Belgrade";
const OVERNIGHT = 1440; // minutes; GTFS times >= this are "after midnight"

function partsInTz(date: Date): { iso: string; minutes: number } {
  const f = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });
  const p: Record<string, string> = {};
  for (const part of f.formatToParts(date)) p[part.type] = part.value;
  const hour = p.hour === "24" ? 0 : Number(p.hour); // some engines emit 24 at midnight
  return { iso: `${p.year}-${p.month}-${p.day}`, minutes: hour * 60 + Number(p.minute) };
}

export function belgradeNow(date: Date): NowContext {
  const today = partsInTz(date);
  const yesterday = partsInTz(new Date(date.getTime() - 24 * 3600 * 1000));
  return { dateISO: today.iso, yesterdayISO: yesterday.iso, minutes: today.minutes };
}

// Active service_ids for a date: the weekday's base services, adjusted by any
// calendar_dates exception for that date (removes then adds).
export function activeServices(dateISO: string, meta: ScheduleMeta): Set<string> {
  const dow = meta.dow[new Date(`${dateISO}T00:00:00Z`).getUTCDay()];
  const active = new Set<string>();
  for (const [svcId, days] of Object.entries(meta.services)) {
    if (days[dow]) active.add(svcId);
  }
  const ex = meta.exceptions[dateISO];
  if (ex) {
    for (const s of ex.remove) active.delete(s);
    for (const s of ex.add) active.add(s);
  }
  return active;
}

/**
 * Upcoming planned departures per line at a stop, from `now`:
 * a departure counts if it's among the next `minTrips` on its line OR within
 * `windowMinutes` (whichever yields more), capped at `maxPerLine`. Overnight is
 * handled from both today's service (times >= now, incl. >=1440 just after
 * midnight) and yesterday's service (times >=1440 mapped to the small hours).
 */
export function upcomingScheduled(
  schedule: StopSchedule,
  meta: ScheduleMeta,
  now: NowContext,
  opts: { minTrips?: number; windowMinutes?: number; maxPerLine?: number; maxEtaMinutes?: number } = {},
): ScheduledArrival[] {
  const minTrips = opts.minTrips ?? 3;
  const windowMinutes = opts.windowMinutes ?? 90;
  const maxPerLine = opts.maxPerLine ?? 10;
  // Hard ceiling on how far ahead a "next arrivals" entry is useful. Also drops
  // the artefact where today's own overnight trips (t >= 1440) sit ~24h out.
  const maxEtaMinutes = opts.maxEtaMinutes ?? 180;
  const todaySvc = activeServices(now.dateISO, meta);
  const yestSvc = activeServices(now.yesterdayISO, meta);

  const out: ScheduledArrival[] = [];
  for (const dep of schedule.deps) {
    const etas: number[] = [];
    for (const [svcId, mins] of Object.entries(dep.svc)) {
      if (todaySvc.has(svcId)) {
        for (const t of mins) if (t >= now.minutes) etas.push(t - now.minutes);
      }
      if (yestSvc.has(svcId)) {
        // Yesterday's overnight trips run in today's small hours (t - 1440).
        for (const t of mins) {
          if (t >= OVERNIGHT) {
            const local = t - OVERNIGHT;
            if (local >= now.minutes) etas.push(local - now.minutes);
          }
        }
      }
    }
    etas.sort((a, b) => a - b);
    let taken = 0;
    for (let i = 0; i < etas.length && taken < maxPerLine; i++) {
      if (etas[i] > maxEtaMinutes) break; // too far out to be useful (sorted)
      if (i < minTrips || etas[i] <= windowMinutes) {
        out.push({ line: dep.line, route_id: dep.route_id, dir: dep.dir, eta_minutes: etas[i] });
        taken++;
      } else {
        break; // sorted: once past both rules, the rest are further out
      }
    }
  }
  out.sort((a, b) => a.eta_minutes - b.eta_minutes);
  return out;
}

/**
 * Drop the scheduled departure that duplicates each live vehicle — the nearest
 * one on the same direction (route_id) within [tolerance] minutes — so the list
 * shows the live vehicle plus the *later* planned trips, not a doubled bus.
 * `liveByRoute`: direction route_id -> live ETAs (minutes).
 */
export function dedupScheduledAgainstLive(
  scheduled: ScheduledArrival[],
  liveByRoute: Map<string, number[]>,
  toleranceMinutes = 20,
): ScheduledArrival[] {
  const removed = new Set<number>(); // indices into `scheduled`
  for (const [routeId, liveEtas] of liveByRoute) {
    const idxs = scheduled
      .map((s, i) => ({ s, i }))
      .filter((x) => x.s.route_id === routeId && !removed.has(x.i));
    for (const liveEta of liveEtas) {
      let best = -1;
      let bestDiff = Infinity;
      for (const { s, i } of idxs) {
        if (removed.has(i)) continue;
        const diff = Math.abs(s.eta_minutes - liveEta);
        if (diff < bestDiff) {
          bestDiff = diff;
          best = i;
        }
      }
      if (best >= 0 && bestDiff <= toleranceMinutes) removed.add(best);
    }
  }
  return scheduled.filter((_, i) => !removed.has(i));
}
