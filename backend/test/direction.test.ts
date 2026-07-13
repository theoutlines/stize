import { describe, expect, it } from "vitest";
import { resolveDirectionRouteId, type DirectionEndpoints } from "../src/lib/direction";

// Real line 53 terminals from the built bundle (lines.json):
//   00053   (dir0): Zeleni venac -> Vidikovac
//   00053-1 (dir1): Vidikovac    -> Zeleni venac
const zeleniVenac = { lat: 44.813812, lon: 20.457314 };
const vidikovac = { lat: 44.731939, lon: 20.420463 };
const line53: DirectionEndpoints[] = [
  { routeId: "00053", origin: zeleniVenac, destination: vidikovac },
  { routeId: "00053-1", origin: vidikovac, destination: zeleniVenac },
];

describe("resolveDirectionRouteId", () => {
  it("picks the direction whose terminals match the vehicle's trip (regression: P21548)", () => {
    // A vehicle whose all_stations runs Vidikovac -> Zeleni venac is on dir1,
    // not the canonical dir0 it used to be stitched to (the 188 m 'through
    // houses' displacement).
    const trip = [vidikovac, { lat: 44.77, lon: 20.44 }, zeleniVenac];
    expect(resolveDirectionRouteId(trip, line53)).toBe("00053-1");
  });

  it("picks the canonical direction for a trip running the other way", () => {
    const trip = [zeleniVenac, { lat: 44.77, lon: 20.44 }, vidikovac];
    expect(resolveDirectionRouteId(trip, line53)).toBe("00053");
  });

  it("returns null (caller falls back) when the trip geometry is missing/too short", () => {
    expect(resolveDirectionRouteId([], line53)).toBeNull();
    expect(resolveDirectionRouteId([zeleniVenac], line53)).toBeNull();
  });

  it("returns null for a single-direction line (nothing to resolve)", () => {
    expect(
      resolveDirectionRouteId([vidikovac, zeleniVenac], [line53[0]]),
    ).toBeNull();
  });

  it("returns null when the two directions are too alike to tell apart", () => {
    // Near-identical terminals (a short loop): endpoints can't distinguish them.
    const a = { lat: 44.8, lon: 20.45 };
    const b = { lat: 44.8005, lon: 20.4505 };
    const loop: DirectionEndpoints[] = [
      { routeId: "L", origin: a, destination: b },
      { routeId: "L-1", origin: b, destination: a },
    ];
    expect(resolveDirectionRouteId([a, b], loop)).toBeNull();
  });
});
