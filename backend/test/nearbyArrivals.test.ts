import { describe, expect, it } from "vitest";
import { groupNearbyArrivals, type StopBoard } from "../src/lib/nearbyArrivals";
import type { ArrivalDto, StopDto, VehicleType } from "../src/types";

function arrival(
  line: string,
  destination: string | null,
  etaMinutes: number,
  extra: Partial<ArrivalDto> = {},
): ArrivalDto {
  return {
    line,
    vehicle_type: "bus" as VehicleType,
    eta_minutes: etaMinutes,
    stops_remaining: null,
    route_id: line,
    gps: null,
    garage_no: null,
    heading: null,
    destination,
    direction_id: null,
    ...extra,
  };
}

function board(
  stopId: string,
  stopName: string,
  distanceMeters: number,
  arrivals: ArrivalDto[],
  updatedAt = "2026-07-12T10:00:00.000Z",
): StopBoard {
  const stop: StopDto = { stop_id: stopId, name: stopName, lat: 0, lon: 0, lines: [] };
  return {
    stop,
    distanceMeters,
    board: {
      stop_id: stopId,
      stop_name: stopName,
      updated_at: updatedAt,
      arrivals,
      service_status: "ok",
    },
  };
}

describe("groupNearbyArrivals", () => {
  it("groups by line + direction (destination), one row per group", () => {
    const groups = groupNearbyArrivals([
      board("A", "Stop A", 100, [
        arrival("79", "Zeleni venac", 5),
        arrival("79", "Blok 45", 8), // same line, opposite direction
      ]),
    ]);
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

  it("distinguishes directions that only differ by direction_id when destination is absent", () => {
    const groups = groupNearbyArrivals([
      board("A", "Stop A", 100, [
        arrival("41", null, 5, { direction_id: "0" }),
        arrival("41", null, 6, { direction_id: "1" }),
      ]),
    ]);
    expect(groups.length).toBe(2);
  });

  it("returns nothing for stops with no arrivals", () => {
    expect(groupNearbyArrivals([board("A", "Stop A", 100, [])])).toEqual([]);
  });
});
