import { describe, expect, it } from "vitest";
import {
  deriveStopTypes,
  applyStopOverrides,
  tramStopsWithoutRail,
  checkBundleShrink,
} from "../scripts/gtfs-core.mjs";

// line → authoritative vehicle type, as built from route_type. The collision
// lines are the point: suffixed buses must NOT inherit a bare tram/trolley type.
const LINE_TYPES = new Map<string, string>([
  ["11", "tram"],
  ["7L", "tram"],
  ["40", "trolleybus"],
  ["3A", "bus"],
  ["49", "bus"],
  ["94", "bus"],
  ["29N", "bus"],
]);

describe("deriveStopTypes — type by feed, not by number", () => {
  it("a 3A/49/94 stop is bus-only (the Topčiderski park defect)", () => {
    expect(deriveStopTypes(["3A", "49", "94"], LINE_TYPES)).toEqual(["bus"]);
  });

  it("orders distinct types tram → trolleybus → bus", () => {
    expect(deriveStopTypes(["94", "40", "11"], LINE_TYPES)).toEqual(["tram", "trolleybus", "bus"]);
  });

  it("a line with no known type falls back to bus, never invents a tram", () => {
    expect(deriveStopTypes(["ADA 3"], LINE_TYPES)).toEqual(["bus"]);
  });
});

describe("applyStopOverrides", () => {
  const seed = () =>
    new Map<string, { lat: number; lon: number }>([
      ["23029", { lat: 44.792503, lon: 20.426776 }],
      ["23030", { lat: 44.791959, lon: 20.426947 }],
    ]);

  const PROV = { reason: "r", date: "2026-07-26", evidence: "e" };

  it("no doc / empty overrides is a no-op (missing file → build unchanged)", () => {
    const stops = seed();
    expect(applyStopOverrides(stops, null).applied).toBe(0);
    expect(applyStopOverrides(stops, { overrides: [] }).applied).toBe(0);
    expect(stops.get("23029")).toEqual({ lat: 44.792503, lon: 20.426776 });
  });

  it("swap_coords swaps the two stops' coordinates", () => {
    const stops = seed();
    const res = applyStopOverrides(stops, {
      overrides: [{ op: "swap_coords", stop_ids: ["23029", "23030"], ...PROV }],
    });
    expect(res.applied).toBe(1);
    expect(stops.get("23029")).toEqual({ lat: 44.791959, lon: 20.426947 });
    expect(stops.get("23030")).toEqual({ lat: 44.792503, lon: 20.426776 });
  });

  it("set_coords sets one stop's coordinate", () => {
    const stops = seed();
    applyStopOverrides(stops, {
      overrides: [{ op: "set_coords", stop_id: "23029", lat: 1, lon: 2, ...PROV }],
    });
    expect(stops.get("23029")).toEqual({ lat: 1, lon: 2 });
  });

  it("refuses an override missing provenance", () => {
    // deliberately malformed (no reason/date/evidence) — cast past the types.
    const bad = { overrides: [{ op: "swap_coords", stop_ids: ["23029", "23030"] }] } as any;
    expect(() => applyStopOverrides(seed(), bad)).toThrow(/provenance/);
  });

  it("throws on a stale stop_id not in the feed", () => {
    expect(() =>
      applyStopOverrides(seed(), { overrides: [{ op: "swap_coords", stop_ids: ["23029", "99999"], ...PROV }] }),
    ).toThrow(/unknown stop_id/);
  });

  it("throws on an unknown op", () => {
    const bad = { overrides: [{ op: "teleport", stop_id: "23029", ...PROV }] } as any;
    expect(() => applyStopOverrides(seed(), bad)).toThrow(/unknown stop override op/);
  });
});

describe("tramStopsWithoutRail — build-time guard", () => {
  // A short tram rail near (44.800, 20.400).
  const rail = [
    [
      [44.8, 20.4],
      [44.8, 20.401],
    ],
  ];

  it("flags a tram-typed stop with no rail within 40 m", () => {
    const stops = [{ stop_id: "X", name: "Far", lat: 44.81, lon: 20.42, types: ["tram"] }];
    const offenders = tramStopsWithoutRail(stops, rail, 40);
    expect(offenders.map((o) => o.stop_id)).toEqual(["X"]);
  });

  it("does not flag a tram-typed stop sitting on the rail", () => {
    const stops = [{ stop_id: "Y", name: "OnRail", lat: 44.8, lon: 20.4005, types: ["tram"] }];
    expect(tramStopsWithoutRail(stops, rail, 40)).toEqual([]);
  });

  it("ignores non-tram stops entirely", () => {
    const stops = [{ stop_id: "Z", name: "Bus", lat: 44.81, lon: 20.42, types: ["bus"] }];
    expect(tramStopsWithoutRail(stops, rail, 40)).toEqual([]);
  });
});

describe("checkBundleShrink — refuse a bundle that lost a merged feed", () => {
  const base = { stops: 3248, lines: 797 };

  it("blocks when stops drop beyond 2% (the dropped-suburban-feed case)", () => {
    // Forgetting the suburban feed drops ~340 lines and their stops.
    const r = checkBundleShrink(base, { stops: 3100, lines: 453 });
    expect(r.blocked).toBe(true);
    expect(r.ok).toBe(false);
    expect(r.problems.map((p) => p.key)).toEqual(["stops", "lines"]);
  });

  it("passes a small shrink within the 2% threshold", () => {
    // ~1% fewer stops, same lines — a normal feed wobble, not a lost feed.
    const r = checkBundleShrink(base, { stops: 3220, lines: 797 });
    expect(r.blocked).toBe(false);
    expect(r.ok).toBe(true);
    expect(r.problems).toEqual([]);
  });

  it("passes growth", () => {
    expect(checkBundleShrink(base, { stops: 3300, lines: 810 }).ok).toBe(true);
  });

  it("blocks at just over 2% but not at exactly 2%", () => {
    expect(checkBundleShrink({ stops: 1000, lines: 100 }, { stops: 980, lines: 100 }).blocked).toBe(false); // −2.0%
    expect(checkBundleShrink({ stops: 1000, lines: 100 }, { stops: 979, lines: 100 }).blocked).toBe(true); // −2.1%
  });

  it("allowShrink lets a big drop through but still reports it", () => {
    const r = checkBundleShrink(base, { stops: 3100, lines: 453 }, { allowShrink: true });
    expect(r.ok).toBe(true);
    expect(r.blocked).toBe(true);
    expect(r.problems.length).toBeGreaterThan(0);
  });

  it("no baseline (first build) always passes", () => {
    expect(checkBundleShrink(null, { stops: 10, lines: 5 }).ok).toBe(true);
  });
});
