import type { Env } from "../env";
import type { ArrivalDto, ArrivalsResponse } from "../types";
import { getWithStaleWhileRevalidate, type WaitUntilCtx } from "./swrCache";
import { BgnaplataTransitProvider, type RawArrival } from "./transitProvider";
import {
  getStopById,
  getLineByNumber,
  getLineDirectionEndpoints,
  getScheduleMeta,
  getStopSchedule,
} from "./gtfsData";
import { resolveDirectionRouteId } from "./direction";
import { belgradeNow, upcomingScheduled, dedupScheduledAgainstLive } from "./schedule";
import { logObservations } from "./analytics";
import { getFlagMemoized } from "./featureFlags";
import { recordVehicleFixes } from "./jamDetector";

const ARRIVALS_TTL_SECONDS = 30;

export async function getArrivals(
  env: Env,
  ctx: WaitUntilCtx,
  stopId: string,
  // The schedule fallback belongs to the arrivals *list* (a thin live board
  // gains planned departures). The map's "vehicles in area" reconstruction
  // (getNearbyVehicles) does NOT want it — scheduled rows carry no GPS and are
  // dropped there anyway, but computing them fans out extra subrequests per
  // stop (getScheduleMeta / getStopSchedule / getLineByNumber). Across an
  // 18-stop map fan-out that alone blew Cloudflare's per-invocation subrequest +
  // CPU limits (→ 503). So the map path passes includeSchedule:false.
  { includeSchedule = true }: { includeSchedule?: boolean } = {},
): Promise<ArrivalsResponse | null> {
  const stop = await getStopById(env, stopId);
  if (!stop) return null;

  const provider = new BgnaplataTransitProvider(env);
  const cacheKeyUrl = `https://cache.stigla.internal/arrivals/${encodeURIComponent(stopId)}`;

  // A dead live board must not take the timetable down with it. The schedule
  // fallback lives below, and it is served entirely from our own GTFS bundle —
  // it does not need the upstream at all. Letting this throw skipped it, so an
  // upstream we couldn't parse turned every stop into an empty board and the app
  // into a "we're taking a short break" wall, while the timetable it already had
  // on hand would have answered the question. Degrade to schedule-only, exactly
  // like a night board, and say so via `service_status`.
  let rawArrivals: RawArrival[] = [];
  let updatedAt = new Date().toISOString();
  let liveOk = true;
  try {
    const live = await getWithStaleWhileRevalidate<RawArrival[]>(
      cacheKeyUrl,
      ARRIVALS_TTL_SECONDS,
      ctx,
      // Wrap the fresh upstream fetch so analytics logs exactly what we just
      // pulled — this runs only on a real refresh (not cache hits), so it adds no
      // extra load on the source. Fire-and-forget; never blocks the response.
      () =>
        provider.fetchArrivals(stopId).then((raw) => {
          ctx.waitUntil(
            logObservations(env, ctx, stopId, raw).catch((e) =>
              console.error("analytics log failed", e),
            ),
          );
          return raw;
        }),
    );
    rawArrivals = live.data;
    updatedAt = live.updatedAt;
  } catch (e) {
    console.error("live board unavailable; serving schedule only", e);
    liveOk = false;
  }

  const arrivals: ArrivalDto[] = [];
  for (const raw of rawArrivals) {
    // Upstream occasionally emits a junk row with no line number. It can't be
    // rendered (a bus icon + "Now" with no line/direction) and can't be
    // filtered client-side, so drop it at the source (F6).
    const lineNumber = raw.lineNumber?.trim();
    if (!lineNumber) {
      console.warn("dropping arrival with empty line number", {
        stopId,
        garageNo: raw.garageNo,
      });
      continue;
    }
    const lineMeta = await getLineByNumber(env, lineNumber);
    const canonicalRouteId = lineMeta?.route_id ?? raw.lineNumber;
    // For mappable vehicles, resolve which direction they're actually on so the
    // map can stitch them to that direction's shape (not always the canonical
    // one). Falls back to canonical when the direction can't be told.
    let directionRouteId = canonicalRouteId;
    if (raw.gps) {
      const directions = await getLineDirectionEndpoints(env, lineNumber);
      directionRouteId =
        resolveDirectionRouteId(raw.routeStations, directions) ?? canonicalRouteId;
    }
    arrivals.push({
      line: lineNumber,
      vehicle_type: lineMeta?.vehicle_type ?? "bus",
      eta_minutes: Math.round(raw.etaSeconds / 60),
      stops_remaining: raw.stopsRemaining,
      route_id: canonicalRouteId,
      direction_route_id: directionRouteId,
      gps: raw.gps,
      garage_no: raw.garageNo,
      heading: raw.heading,
      // Forward timing plan. `raw.trajectory` is undefined on a stale pre-deploy
      // cache entry; treat that the same as "no plan" so an old cache never
      // breaks the response.
      trajectory:
        raw.trajectory?.map((p) => ({
          lat: p.lat,
          lon: p.lon,
          eta_seconds: p.etaSeconds,
        })) ?? null,
    });
  }
  arrivals.sort((a, b) => a.eta_minutes - b.eta_minutes);

  // Schedule fallback (Phase 1): append planned departures so a thin/empty live
  // board (night, inter-peak) still shows what's coming, deduped against the
  // live rows so a bus with a live vehicle isn't doubled. Only the arrivals list
  // asks for it (includeSchedule); the map fan-out passes includeSchedule:false
  // so an 18-stop fan-out never pays this cost (→ 503). Failure degrades
  // silently to the live-only board.
  if (includeSchedule) {
    try {
      const [meta, schedule] = await Promise.all([
        getScheduleMeta(env),
        getStopSchedule(env, stopId),
      ]);
      if (meta && schedule) {
        let scheduled = upcomingScheduled(schedule, meta, belgradeNow(new Date()));
        // Dedup against every live row (real or placeholder) on the same
        // direction: drop the nearest planned trip, keep the later tail.
        const liveByRoute = new Map<string, number[]>();
        for (const a of arrivals) {
          const key = a.direction_route_id ?? a.route_id;
          (liveByRoute.get(key) ?? liveByRoute.set(key, []).get(key)!).push(a.eta_minutes);
        }
        scheduled = dedupScheduledAgainstLive(scheduled, liveByRoute);
        for (const s of scheduled) {
          const lm = await getLineByNumber(env, s.line);
          arrivals.push({
            line: s.line,
            vehicle_type: lm?.vehicle_type ?? "bus",
            eta_minutes: s.eta_minutes,
            stops_remaining: null,
            route_id: s.route_id,
            direction_route_id: s.route_id,
            gps: null,
            garage_no: null,
            heading: null,
            source: "scheduled",
          });
        }
        arrivals.sort((a, b) => a.eta_minutes - b.eta_minutes);
      }
    } catch (e) {
      console.error("schedule fallback failed", e);
    }
  }

  // Jam detection (Variant B): opportunistically record this board's live fixes
  // into the last-fix table. Fire-and-forget, flag-gated, no extra upstream call
  // — it rides the board we already fetched. The upsert only bumps a vehicle's
  // freeze clock on a genuinely newer board (re-reads are no-ops), so this is
  // safe to fire on every call. Never blocks or fails the response.
  if (liveOk) {
    const boardAt = Date.parse(updatedAt);
    if (!Number.isNaN(boardAt)) {
      ctx.waitUntil(
        getFlagMemoized(env, ctx, "jam_detection_show").then((on) =>
          on
            ? recordVehicleFixes(env, boardAt, arrivals, Date.now()).catch((e) =>
                console.error("jam fix record failed", e),
              )
            : undefined,
        ),
      );
    }
  }

  return {
    stop_id: stop.stop_id,
    stop_name: stop.name,
    updated_at: updatedAt,
    arrivals,
    // "unavailable" now means "no LIVE data" — not "no data". The rows may still
    // be a full timetable; the client says so with a banner rather than a wall.
    service_status: liveOk ? "ok" : "unavailable",
  };
}
