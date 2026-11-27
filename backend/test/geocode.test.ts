import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:test";
import { BELGRADE_BOUNDS, geocodeSearch, insideBelgrade, poiKind } from "../src/lib/geocode";
import { getAllStops } from "../src/lib/gtfsData";

afterEach(() => vi.unstubAllGlobals());

describe("geocode stays in Belgrade", () => {
  it("every stop in the feed is inside the bounds", async () => {
    const stops = await getAllStops(env);
    expect(stops.filter((s) => !insideBelgrade(s.lat, s.lon))).toEqual([]);
  });

  it("asks Nominatim for Serbia inside the box and drops anything outside", async () => {
    let asked: URL | null = null;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      asked = new URL(input instanceof Request ? input.url : String(input));
      return Response.json([
        { display_name: "830, 馬山區", name: "830", lat: "37.2", lon: "128.5" },
        { display_name: "830, White Oak", name: "830", lat: "39.1", lon: "-77.0" },
        { display_name: "Gradska bolnica, Vračar", name: "Gradska bolnica", lat: "44.80", lon: "20.47" },
      ]);
    });
    const results = await geocodeSearch(env, `bounds-test-${Date.now()}`);
    expect(results.map((r) => r.display_name)).toEqual(["Gradska bolnica"]);
    expect(asked!.searchParams.get("bounded")).toBe("1");
    expect(asked!.searchParams.get("countrycodes")).toBe("rs");
    const [w, n, e, s] = asked!.searchParams.get("viewbox")!.split(",").map(Number);
    expect([w, n, e, s]).toEqual([BELGRADE_BOUNDS.west, BELGRADE_BOUNDS.north, BELGRADE_BOUNDS.east, BELGRADE_BOUNDS.south]);
  });
});

describe("a found place carries the badge it has on the map", () => {
  it("maps OSM tags to the basemap POI class", () => {
    expect(poiKind("historic", "fortress")).toBe("castle");
    expect(poiKind("tourism", "museum")).toBe("museum");
    expect(poiKind("shop", "shoes")).toBe("shop");
    expect(poiKind("leisure", "park")).toBe("park");
  });

  it("streets, addresses and unknown kinds have none", () => {
    expect(poiKind("highway", "residential")).toBeNull();
    expect(poiKind("place", "house")).toBeNull();
    expect(poiKind(undefined, undefined)).toBeNull();
  });

  it("returns the kind with each result", async () => {
    vi.stubGlobal("fetch", async () =>
      Response.json([
        { display_name: "Muzej, Stari grad", name: "Muzej", category: "tourism", type: "museum", lat: "44.81", lon: "20.46" },
        { display_name: "Knez Mihailova, Stari grad", category: "highway", type: "pedestrian", lat: "44.815", lon: "20.457" },
      ]),
    );
    const results = await geocodeSearch(env, `kind-test-${Date.now()}`);
    expect(results.map((r) => r.kind)).toEqual(["museum", null]);
  });
});
