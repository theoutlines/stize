import { describe, expect, it } from "vitest";
import {
  activeServices,
  belgradeNow,
  upcomingScheduled,
  dedupScheduledAgainstLive,
  scheduledMapObjectsForRoute,
  type ScheduleMeta,
  type StopSchedule,
  type NowContext,
  type TripTimed,
} from "../src/lib/schedule";

const meta: ScheduleMeta = {
  unit: "minutes",
  dow: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
  services: {
    RD: { monday: 1, tuesday: 1, wednesday: 1, thursday: 1, friday: 1, saturday: 0, sunday: 0 },
    S: { monday: 0, tuesday: 0, wednesday: 0, thursday: 0, friday: 0, saturday: 1, sunday: 0 },
    N: { monday: 0, tuesday: 0, wednesday: 0, thursday: 0, friday: 0, saturday: 0, sunday: 1 },
  },
  // 2026-01-01 is a Thursday (weekday) holiday: run the Sunday service instead.
  exceptions: { "2026-01-01": { add: ["N"], remove: ["RD"] } },
};

describe("activeServices", () => {
  it("weekday -> RD, Saturday -> S, Sunday -> N", () => {
    expect([...activeServices("2026-01-02", meta)]).toEqual(["RD"]); // Fri
    expect([...activeServices("2026-01-03", meta)]).toEqual(["S"]); // Sat
    expect([...activeServices("2026-01-04", meta)]).toEqual(["N"]); // Sun
  });

  it("holiday on a weekday swaps RD->N via calendar_dates", () => {
    expect([...activeServices("2026-01-01", meta)]).toEqual(["N"]); // Thu holiday
  });
});

describe("belgradeNow (timezone)", () => {
  it("summer is UTC+2", () => {
    const n = belgradeNow(new Date("2026-07-15T00:30:00Z"));
    expect(n.dateISO).toBe("2026-07-15");
    expect(n.minutes).toBe(150); // 02:30 local
  });
  it("winter is UTC+1 and rolls the date past local midnight", () => {
    const n = belgradeNow(new Date("2026-01-15T23:30:00Z"));
    expect(n.dateISO).toBe("2026-01-16"); // 00:30 local next day
    expect(n.minutes).toBe(30);
    expect(n.yesterdayISO).toBe("2026-01-15");
  });
});

function sched(svc: Record<string, number[]>): StopSchedule {
  return { stop_id: "1", deps: [{ line: "10", route_id: "00010", dir: "0", svc }] };
}
const friday: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 595 }; // 09:55

describe("upcomingScheduled", () => {
  it("frequent line: next 3 within 90 min", () => {
    const r = upcomingScheduled(sched({ RD: [600, 610, 620, 700, 800] }), meta, friday);
    expect(r.map((x) => x.eta_minutes)).toEqual([5, 15, 25]);
  });

  it("sparse line: still returns the next 3 even beyond 90 min (whichever is more)", () => {
    const r = upcomingScheduled(sched({ RD: [600, 700, 745] }), meta, friday); // +5, +105, +150
    expect(r.map((x) => x.eta_minutes)).toEqual([5, 105, 150]);
  });

  it("uses the active service only (Sunday times ignored on a weekday)", () => {
    const r = upcomingScheduled(sched({ RD: [600], N: [601] }), meta, friday);
    expect(r.map((x) => x.eta_minutes)).toEqual([5]);
  });

  it("overnight: yesterday's after-midnight trips show in the small hours", () => {
    // Now 00:30 Saturday; Friday(RD) had a 24:30 (=1470) trip -> runs Sat 00:30.
    const now: NowContext = { dateISO: "2026-01-03", yesterdayISO: "2026-01-02", minutes: 30 };
    const r = upcomingScheduled(sched({ RD: [1470], S: [1470] }), meta, now);
    // RD (yesterday) 1470 -> local 00:30 -> eta 0. S (today) 1470 -> ~24h, dropped.
    expect(r.map((x) => x.eta_minutes)).toEqual([0]);
  });
});

describe("dedupScheduledAgainstLive", () => {
  it("drops the planned trip nearest each live vehicle, keeps the tail", () => {
    const scheduled = upcomingScheduled(sched({ RD: [600, 620, 640] }), meta, friday); // +5,+25,+45
    const live = new Map<string, number[]>([["00010", [6]]]); // a live bus ~6 min out
    const kept = dedupScheduledAgainstLive(scheduled, live);
    // The +5 planned trip (closest to live 6) is dropped; +25/+45 stay as the tail.
    expect(kept.map((x) => x.eta_minutes)).toEqual([25, 45]);
  });

  it("keeps planned trips when the live vehicle is on a different direction", () => {
    const scheduled = upcomingScheduled(sched({ RD: [600, 620] }), meta, friday);
    const live = new Map<string, number[]>([["00010-1", [6]]]); // other direction
    expect(dedupScheduledAgainstLive(scheduled, live)).toHaveLength(2);
  });

  it("does not drop a far tail when live is far from any planned trip", () => {
    const scheduled = upcomingScheduled(sched({ RD: [600, 620] }), meta, friday); // +5,+25
    const live = new Map<string, number[]>([["00010", [90]]]); // 90 min out, beyond tolerance
    expect(dedupScheduledAgainstLive(scheduled, live)).toHaveLength(2);
  });
});

describe("scheduledMapObjectsForRoute", () => {
  // A straight 3-stop route heading east, ~1.4 km apart.
  const coords = [
    { lat: 44.80, lon: 20.40 },
    { lat: 44.80, lon: 20.42 },
    { lat: 44.80, lon: 20.44 },
  ];
  // A trip departs each stop at 10:00 / 10:10 / 10:20 (weekday service).
  const trips: TripTimed[] = [{ trip_id: "T1", service: "RD", times: [600, 610, 620] }];

  it("places an in-transit trip between its two current stops with a forward trajectory", () => {
    const now: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 605 }; // 10:05
    const objs = scheduledMapObjectsForRoute(trips, coords, meta, now);
    expect(objs).toHaveLength(1);
    const o = objs[0];
    // Halfway between stop 0 (10:00) and stop 1 (10:10).
    expect(o.lon).toBeCloseTo(20.41, 3);
    expect(o.heading).toBeCloseTo(90, 0); // due east
    // Trajectory: current pos (eta 0), then stop1 (+5 min), stop2 (+15 min).
    expect(o.trajectory.map((p) => p.eta_seconds)).toEqual([0, 300, 900]);
  });

  it("omits trips not currently in transit", () => {
    const before: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 590 }; // 09:50
    expect(scheduledMapObjectsForRoute(trips, coords, meta, before)).toHaveLength(0);
    const after: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 630 }; // 10:30
    expect(scheduledMapObjectsForRoute(trips, coords, meta, after)).toHaveLength(0);
  });

  it("ignores trips whose service isn't active today", () => {
    const sundayTrip: TripTimed[] = [{ trip_id: "N1", service: "N", times: [600, 610, 620] }];
    const weekday: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 605 };
    expect(scheduledMapObjectsForRoute(sundayTrip, coords, meta, weekday)).toHaveLength(0);
  });

  it("places a trip sitting exactly on its final timepoint at the terminus (no throw)", () => {
    // now === last stop time (10:20). Previously the segment loop overran and
    // reading pts[i+1].t threw a TypeError, dropping every scheduled object.
    const atTerminus: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 620 };
    const objs = scheduledMapObjectsForRoute(trips, coords, meta, atTerminus);
    expect(objs).toHaveLength(1);
    expect(objs[0].lon).toBeCloseTo(20.44, 3); // last stop
    expect(objs[0].trajectory[0].eta_seconds).toBe(0);
  });

  it("mixes normal + at-terminus + not-in-transit trips without one edge dropping the rest", () => {
    // Regression for the swallowed TypeError: a route whose trip list mixes a
    // mid-segment trip (renders), a trip exactly at its terminus (used to throw),
    // and a trip not in transit (skipped) must return both renderable objects.
    const now: NowContext = { dateISO: "2026-01-02", yesterdayISO: "2026-01-01", minutes: 620 }; // 10:20
    const mixed: TripTimed[] = [
      { trip_id: "MID", service: "RD", times: [615, 625, 635] }, // 10:15..10:35, mid first segment
      { trip_id: "END", service: "RD", times: [600, 610, 620] }, // 10:00..10:20, exactly at terminus
      { trip_id: "GONE", service: "RD", times: [500, 510, 520] }, // already finished
    ];
    const objs = scheduledMapObjectsForRoute(mixed, coords, meta, now);
    expect(objs.map((o) => o.trip_id).sort()).toEqual(["END", "MID"]);
  });

  it("runs yesterday's overnight trip in today's small hours", () => {
    // Friday(RD) trip 24:00/24:10/24:20 -> runs Sat 00:00..00:20.
    const overnight: TripTimed[] = [{ trip_id: "O1", service: "RD", times: [1440, 1450, 1460] }];
    const satEarly: NowContext = { dateISO: "2026-01-03", yesterdayISO: "2026-01-02", minutes: 5 }; // 00:05
    const objs = scheduledMapObjectsForRoute(overnight, coords, meta, satEarly);
    expect(objs).toHaveLength(1);
    expect(objs[0].lon).toBeCloseTo(20.41, 3); // halfway stop0->stop1
  });
});
