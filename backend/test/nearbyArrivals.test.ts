import { describe, expect, it } from "vitest";
import {
  groupNearbyArrivals,
  nearbyServiceStatus,
  timeToBoardMinutes,
  type StopBoard,
} from "../src/lib/nearbyArrivals";
import type { ArrivalDto, StopDto, VehicleType } from "../src/types";

// `direction` doubles as the arrival's direction route_id (the grouping key) and,
// via [dests] below, its display name — mirroring how getNearbyArrivals groups by
// `direction_route_id` and resolves the terminus name from GTFS line metadata.
function arrival(
  line: string,
  direction: string | null,
  etaMinutes: number,
  extra: Partial<ArrivalDto> = {},
): ArrivalDto {
  return {
    line,
    vehicle_type: "bus" as VehicleType,
    eta_minutes: etaMinutes,
    stops_remaining: null,
    route_id: line,
    direction_route_id: direction ?? line,
    gps: null,
    garage_no: null,
    heading: null,
    ...extra,
  };
}

// Build the route_id → destination-name map the way getNearbyArrivals does, but
// for tests we let the direction key be its own display name.
function dests(...names: string[]): Map<string, string | null> {
  const m = new Map<string, string | null>();
  for (const n of names) m.set(n, n);
  return m;
}

function board(
  stopId: string,
  stopName: string,
  distanceMeters: number,
  arrivals: ArrivalDto[],
  updatedAt = "2026-07-12T10:00:00.000Z",
  serviceStatus: "ok" | "unavailable" = "ok",
): StopBoard {
  const stop: StopDto = { stop_id: stopId, name: stopName, lat: 0, lon: 0, lines: [] };
  return {
    stop,
    distanceMeters,
    board: {
      updated_at: updatedAt,
      arrivals,
      service_status: serviceStatus,
    },
  };
}

describe("groupNearbyArrivals", () => {
  it("groups by line + direction (direction_route_id), one row per group", () => {
    const groups = groupNearbyArrivals(
      [
        board("A", "Stop A", 100, [
          arrival("79", "Zeleni venac", 5),
          arrival("79", "Blok 45", 8), // same line, opposite direction
        ]),
      ],
      dests("Zeleni venac", "Blok 45"),
    );
    expect(groups.length).toBe(2);
    expect(new Set(groups.map((g) => g.destination))).toEqual(
      new Set(["Zeleni venac", "Blok 45"]),
    );
  });

  it("dedups a line+direction to the nearest stop that serves it", () => {
    const groups = groupNearbyArrivals([
      board("A", "Near stop", 100, [arrival("83", "Kneževac", 4)]),
      board("B", "Far stop", 300, [arrival("83", "Kneževac", 2)]),
    ]);
    expect(groups.length).toBe(1);
    // The nearest stop wins, even though the far one had a sooner ETA.
    expect(groups[0].stop_name).toBe("Near stop");
    expect(groups[0].distance_meters).toBe(100);
    expect(groups[0].arrivals[0].eta_minutes).toBe(4);
  });

  it("keeps the two soonest departures at the nearest stop, sorted", () => {
    const groups = groupNearbyArrivals([
      board("A", "Near stop", 50, [
        arrival("26", "Dorćol", 9),
        arrival("26", "Dorćol", 3),
        arrival("26", "Dorćol", 6),
      ]),
    ]);
    expect(groups.length).toBe(1);
    expect(groups[0].arrivals.map((a) => a.eta_minutes)).toEqual([3, 6]);
  });

  it("sorts rows by the soonest ETA, tie-broken by distance", () => {
    const groups = groupNearbyArrivals([
      board("A", "Stop A", 120, [arrival("1", "North", 7)]),
      board("B", "Stop B", 80, [arrival("2", "South", 2)]),
      board("C", "Stop C", 200, [arrival("3", "East", 7)]),
    ]);
    expect(groups.map((g) => g.line)).toEqual(["2", "1", "3"]);
  });

  it("distinguishes the two directions of a line by their direction_route_id", () => {
    const groups = groupNearbyArrivals([
      board("A", "Stop A", 100, [
        arrival("41", "41-0", 5),
        arrival("41", "41-1", 6),
      ]),
    ]);
    expect(groups.length).toBe(2);
  });

  it("returns nothing for stops with no arrivals", () => {
    expect(groupNearbyArrivals([board("A", "Stop A", 100, [])])).toEqual([]);
  });

  it("carries the scheduled/live source through to each eta (never-empty tail)", () => {
    const groups = groupNearbyArrivals([
      board("A", "Stop A", 100, [
        arrival("83", "Kneževac", 3, { source: "live" }),
        arrival("83", "Kneževac", 12, { source: "scheduled" }),
      ]),
    ]);
    expect(groups.length).toBe(1);
    expect(groups[0].arrivals.map((a) => a.source)).toEqual(["live", "scheduled"]);
  });
});

describe("timeToBoardMinutes", () => {
  it("returns the soonest departure you can still catch", () => {
    // 43 m ≈ 0.5 min walk; the 5-min bus is easily reachable.
    expect(timeToBoardMinutes(43, [5, 23])).toBe(5);
  });

  it("skips a departure you can't walk to in time, taking the next reachable one", () => {
    // 300 m ≈ 3.75 min walk: the 2-min bus is missed, the 10-min one is caught.
    expect(timeToBoardMinutes(300, [2, 10])).toBe(10);
  });

  it("penalises a stop whose only listed departure is unreachable", () => {
    // 294 m ≈ 3.68 min walk, only a 2-min bus listed → missed → walk + penalty.
    const t = timeToBoardMinutes(294, [2]);
    expect(t).toBeGreaterThan(5); // sorts below a reachable 5-min bus
  });

  it("allows a one-minute hustle to just catch a departure", () => {
    // 150 m ≈ 1.875 min walk vs a 1-min bus: within the 1-min grace → catch it.
    expect(timeToBoardMinutes(150, [1])).toBe(1);
  });
});

describe("groupNearbyArrivals — board sort", () => {
  it('by "board", a close later bus outranks a far sooner-but-unreachable one', () => {
    // Mirrors the reported case: line 62 is 2 min away but 294 m off (you'd miss
    // it), line 79 is 5 min away but 43 m off (you make it). By ETA, 62 sorts
    // first; by time-to-board, 79 should.
    const groups = groupNearbyArrivals(
      [
        board("near", "Batutova", 43, [arrival("79", "Dorćol", 5)]),
        board("far", "Škola", 294, [arrival("62", "Zvezdara", 2)]),
      ],
      new Map(),
      "board",
    );
    expect(groups.map((g) => g.line)).toEqual(["79", "62"]);
  });

  it('by "eta" (default), the sooner bus still sorts first regardless of distance', () => {
    const groups = groupNearbyArrivals([
      board("near", "Batutova", 43, [arrival("79", "Dorćol", 5)]),
      board("far", "Škola", 294, [arrival("62", "Zvezdara", 2)]),
    ]);
    expect(groups.map((g) => g.line)).toEqual(["62", "79"]);
  });
});

describe("nearbyServiceStatus", () => {
  it("is unavailable only when every present board is live-down", () => {
    expect(nearbyServiceStatus(["unavailable", "unavailable"])).toBe("unavailable");
  });
  it("stays ok if any nearby stop still has live data", () => {
    expect(nearbyServiceStatus(["unavailable", "ok"])).toBe("ok");
  });
  it("is ok with no boards at all (nothing nearby, not an outage)", () => {
    expect(nearbyServiceStatus([])).toBe("ok");
  });
});
