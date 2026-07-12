import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  getLineByNumber,
  getLineDirections,
  getRouteShape,
  getStopById,
  nearbyStops,
  nearestStop,
  searchLines,
  searchStops,
} from "../src/lib/gtfsData";

describe("gtfsData (against the real built GTFS bundle)", () => {
  it("finds the Batutova stop used as the smoke-test stop", async () => {
    const stop = await getStopById(env, "20091");
    expect(stop?.name).toBe("Batutova");
    expect(stop?.lines).toContain("79");
  });

  it("searches stops by name, case-insensitively", async () => {
    const results = await searchStops(env, "batutova");
    expect(results.length).toBeGreaterThanOrEqual(4);
    expect(results.every((s) => s.name.toLowerCase().includes("batutova"))).toBe(true);
  });

  it("returns nearby stops sorted by distance", async () => {
    const results = await nearbyStops(env, 44.795374, 20.499713, 200);
    expect(results[0].stop_id).toBe("20091"); // itself, distance 0
  });

  it("looks up a line by number and its route shape", async () => {
    const line = await getLineByNumber(env, "79");
    expect(line?.route_id).toBe("00079");
    expect(line?.vehicle_type).toBe("bus");

    const shape = await getRouteShape(env, "00079");
    expect(shape?.polyline.length).toBeGreaterThan(0);
    expect(shape?.stops.some((s) => s.stop_id === "20529")).toBe(true);
  });

  it("surfaces both directions of a line in search (F8)", async () => {
    const l79 = (await searchLines(env, "79")).filter((l) => l.line === "79");
    expect(l79.length).toBe(2);
    // Opposite directions, distinguished by direction_id and swapped endpoints.
    expect(new Set(l79.map((l) => l.direction_id))).toEqual(new Set(["0", "1"]));
    const [a, b] = l79;
    expect(a.origin).toBe(b.destination);
    expect(a.destination).toBe(b.origin);
  });

  it("resolves each direction's own shape by its route key (F8)", async () => {
    const l79 = (await searchLines(env, "79")).filter((l) => l.line === "79");
    for (const l of l79) {
      const shape = await getRouteShape(env, l.route_id);
      expect(shape?.polyline.length).toBeGreaterThan(0);
    }
    // The non-canonical direction is keyed with a suffix, not the bare id.
    expect(l79.map((l) => l.route_id).sort()).toEqual(["00079", "00079-1"]);
  });

  it("by-number lookup returns the canonical direction (F8)", async () => {
    const line = await getLineByNumber(env, "79");
    expect(line?.route_id).toBe("00079"); // bare id, never a "-1" suffix
  });

  it("resolves the nearest stop to a coordinate (terminus → direction name)", async () => {
    // A point right on the Batutova stop resolves to it.
    const stop = await nearestStop(env, { lat: 44.795374, lon: 20.499713 });
    expect(stop?.stop_id).toBe("20091");
  });

  it("returns both directions of a line for direction matching (F8)", async () => {
    const directions = await getLineDirections(env, "79");
    expect(directions.length).toBe(2);
    expect(new Set(directions.map((d) => d.direction_id))).toEqual(new Set(["0", "1"]));
  });

  it("returns an empty array for a query that matches nothing", async () => {
    expect(await searchStops(env, "zzzznotarealstopzzzz")).toEqual([]);
    expect(await searchLines(env, "zzzznotarealline")).toEqual([]);
  });

  it("returns null for an unknown route_id", async () => {
    expect(await getRouteShape(env, "not-a-real-route")).toBeNull();
  });
});
