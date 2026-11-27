import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  getFeedMeta,
  getLineByNumber,
  getRouteShape,
  getStopById,
  nearbyStops,
  searchLines,
  searchStops,
  stopCode,
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

  it("finds a stop by the number on its sign (stop_id − 20000)", async () => {
    const results = await searchStops(env, "830");
    expect(results[0].stop_id).toBe("20830");
    expect(results[0].name).toBe("Škola Vojislav Ilić");
    // Leading zeros are the same number.
    expect((await searchStops(env, "0830"))[0].stop_id).toBe("20830");
  });

  it("from three digits, numbers that start with the query follow the exact one", async () => {
    // No stop 124 exists; 1240…1249 do, in number order.
    const codes = (await searchStops(env, "124")).map((s) => stopCode(s.stop_id));
    expect(codes.slice(0, 3)).toEqual(["1240", "1241", "1242"]);
    expect((await searchStops(env, "830")).map((s) => stopCode(s.stop_id))[0]).toBe("830");
  });

  it("two digits find only the exact number, never a pile of prefixes", async () => {
    const results = await searchStops(env, "83");
    expect(stopCode(results[0].stop_id)).toBe("83");
    expect(results.some((s) => stopCode(s.stop_id) === "830")).toBe(false);
  });

  it("still matches names that contain the digits", async () => {
    const results = await searchStops(env, "25");
    expect(results.some((s) => s.name === "Blok 25")).toBe(true);
  });

  it("maps stop ids to sign numbers and refuses other schemes", () => {
    expect(stopCode("20830")).toBe("830");
    expect(stopCode("21106")).toBe("1106");
    expect(stopCode("830")).toBeNull();
    expect(stopCode("10830")).toBeNull();
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

  it("returns an empty array for a query that matches nothing", async () => {
    expect(await searchStops(env, "zzzznotarealstopzzzz")).toEqual([]);
    expect(await searchLines(env, "zzzznotarealline")).toEqual([]);
  });

  it("returns null for an unknown route_id", async () => {
    expect(await getRouteShape(env, "not-a-real-route")).toBeNull();
  });

  it("exposes bundle freshness metadata (feed_meta.json)", async () => {
    const meta = await getFeedMeta(env);
    expect(meta).not.toBeNull();
    // ISO dates (or null), a build timestamp, and the bundle counts.
    expect(meta?.feed_start_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(meta?.built_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(meta?.counts.stops).toBeGreaterThan(0);
    expect(meta?.counts.lines).toBeGreaterThan(0);
  });

  it("stops.compact.json matches stops.json (regenerate with scripts/compact-stops.mjs)", async () => {
    const full = (await (await env.ASSETS.fetch("https://assets.local/gtfs/stops.json")).json()) as {
      stops: { stop_id: string; name: string; lat: number; lon: number; lines: string[]; types?: string[] }[];
    };
    for (const s of full.stops.filter((_, i) => i % 97 === 0)) {
      const got = await getStopById(env, s.stop_id);
      expect(got).toMatchObject({ stop_id: s.stop_id, name: s.name, lat: s.lat, lon: s.lon, lines: s.lines });
      expect(got?.types ?? []).toEqual(s.types ?? []);
    }
    const compact = (await (await env.ASSETS.fetch("https://assets.local/gtfs/stops.compact.json")).json()) as {
      stop_id: string[];
    };
    expect(compact.stop_id.length).toBe(full.stops.length);
  });
});
