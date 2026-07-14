import { describe, expect, it } from "vitest";
import { headingFromRoute, parseRawArrival, parseTrajectory } from "../src/lib/transitProvider";
import type { ArrivalDto } from "../src/types";

// Shape based on a real captured response for stop 20091 (Batutova, line 79).
const SAMPLE_RAW_ITEM = {
  just_coordinates: "0",
  seconds_left: 1152,
  line_number: "79",
  station_name: "Batutova",
  id: "4935",
  actual_line_number: "4454B",
  stations_between: 11,
  garage_no: "P26624",
  vehicles: [{ garageNo: "P26624", lat: "44.79091000", lng: "20.54057160", station_name: "Semjuela Beketa" }],
};

describe("parseRawArrival", () => {
  it("normalizes a well-formed upstream item", () => {
    const result = parseRawArrival(SAMPLE_RAW_ITEM);
    expect(result).toEqual({
      lineNumber: "79",
      etaSeconds: 1152,
      stopsRemaining: 11,
      garageNo: "P26624",
      gps: { lat: 44.79091, lon: 20.5405716 },
      heading: null, // no all_stations in this sample
      trajectory: null, // no all_stations timing in this sample
      routeStations: [],
    });
  });

  it("falls back to nulls/zeros when optional fields are missing", () => {
    const result = parseRawArrival({ line_number: "5" });
    expect(result).toEqual({
      lineNumber: "5",
      etaSeconds: 0,
      stopsRemaining: null,
      garageNo: null,
      gps: null,
      heading: null,
      trajectory: null,
      routeStations: [],
    });
  });

  it("treats a non-numeric gps payload as absent", () => {
    const result = parseRawArrival({ line_number: "5", vehicles: [{ lat: null, lng: null }] });
    expect(result.gps).toBeNull();
  });

  it("attaches a forward timing plan when all_stations carries route timing", () => {
    const result = parseRawArrival({
      line_number: "79",
      vehicles: [{ lat: "44.7930", lng: "20.5390" }],
      all_stations: [
        { coordinates: { latitude: "44.7862", longitude: "20.5456" }, second_left_by_route: 0 }, // behind
        { coordinates: { latitude: "44.7937", longitude: "20.5366" }, second_left_by_route: 34 }, // ahead
        { coordinates: { latitude: "44.7941", longitude: "20.5340" }, second_left_by_route: 164 },
      ],
    });
    expect(result.trajectory).toEqual([
      { lat: 44.793, lon: 20.539, etaSeconds: 0 }, // current GPS anchors the plan
      { lat: 44.7937, lon: 20.5366, etaSeconds: 34 },
      { lat: 44.7941, lon: 20.534, etaSeconds: 164 },
    ]);
  });

  it("derives a heading from all_stations geometry when GPS is present", () => {
    const result = parseRawArrival({
      line_number: "79",
      vehicles: [{ lat: "44.8000", lng: "20.5000" }],
      all_stations: [
        { coordinates: { latitude: "44.8000", longitude: "20.5000" } },
        { coordinates: { latitude: "44.8100", longitude: "20.5000" } }, // due north
      ],
    });
    expect(result.heading).not.toBeNull();
    expect(result.heading!).toBeCloseTo(0, 0); // heading north
  });
});

describe("headingFromRoute", () => {
  it("returns due east as ~90 degrees", () => {
    const h = headingFromRoute({ lat: 44.8, lon: 20.5 }, [
      { lat: 44.8, lon: 20.5 },
      { lat: 44.8, lon: 20.51 }, // east
    ]);
    expect(h).toBeCloseTo(90, 0);
  });

  it("orients toward the next station along the route, not backward", () => {
    // Vehicle sits at the middle station of a west->east line; must head east.
    const h = headingFromRoute({ lat: 44.8, lon: 20.5 }, [
      { lat: 44.8, lon: 20.49 },
      { lat: 44.8, lon: 20.5 },
      { lat: 44.8, lon: 20.51 },
    ]);
    expect(h).toBeCloseTo(90, 0);
  });

  it("uses the segment the vehicle is on, not the nearest station's next hop", () => {
    // L-shaped route: A->B goes east, B->C turns north. The vehicle is still on
    // the A->B leg but nearer to station B than to A. Snapping to the nearest
    // station (B) would have taken the B->C bearing (north); projecting onto the
    // segment keeps it heading east along the leg it's actually on.
    const h = headingFromRoute({ lat: 44.8, lon: 20.5085 }, [
      { lat: 44.8, lon: 20.5 }, // A
      { lat: 44.8, lon: 20.51 }, // B (east of A)
      { lat: 44.81, lon: 20.51 }, // C (north of B)
    ]);
    expect(h).toBeCloseTo(90, 0);
  });

  it("returns null with fewer than two stations", () => {
    expect(headingFromRoute({ lat: 44.8, lon: 20.5 }, [])).toBeNull();
    expect(headingFromRoute({ lat: 44.8, lon: 20.5 }, [{ lat: 44.8, lon: 20.5 }])).toBeNull();
  });
});

describe("trajectory is an additive field (old contract unbroken)", () => {
  // The old arrivals contract has no `trajectory`. The field is optional, so
  // with the feature off (undefined) the serialized JSON is byte-identical to
  // the pre-feature shape — old clients see nothing new. With it on, the plan
  // appears under `trajectory` and nothing else changes.
  const base: ArrivalDto = {
    line: "79",
    vehicle_type: "bus",
    eta_minutes: 5,
    stops_remaining: 3,
    route_id: "4454B",
    gps: { lat: 44.79, lon: 20.54 },
    garage_no: "P26624",
    heading: 90,
  };

  it("omits the key entirely when the plan is off", () => {
    const json = JSON.parse(JSON.stringify({ ...base, trajectory: undefined }));
    expect("trajectory" in json).toBe(false);
    expect(json).toEqual(base);
  });

  it("adds only the trajectory key when the plan is on", () => {
    const withPlan: ArrivalDto = {
      ...base,
      trajectory: [
        { lat: 44.79, lon: 20.54, eta_seconds: 0 },
        { lat: 44.8, lon: 20.53, eta_seconds: 40 },
      ],
    };
    const json = JSON.parse(JSON.stringify(withPlan));
    expect(json.trajectory).toHaveLength(2);
    expect(json.trajectory[0]).toEqual({ lat: 44.79, lon: 20.54, eta_seconds: 0 });
    // Every other field is unchanged from the base contract.
    const { trajectory: _t, ...rest } = json;
    expect(rest).toEqual(base);
  });
});

describe("parseTrajectory", () => {
  const gps = { lat: 44.79, lon: 20.54 };

  it("prepends the current GPS at eta 0 and lists stations ahead in order", () => {
    const plan = parseTrajectory(gps, [
      { coordinates: { latitude: "44.80", longitude: "20.53" }, second_left_by_route: 40 },
      { coordinates: { latitude: "44.81", longitude: "20.52" }, second_left_by_route: 120 },
    ]);
    expect(plan).toEqual([
      { lat: 44.79, lon: 20.54, etaSeconds: 0 },
      { lat: 44.8, lon: 20.53, etaSeconds: 40 },
      { lat: 44.81, lon: 20.52, etaSeconds: 120 },
    ]);
  });

  it("skips stations behind the vehicle (eta 0) and non-increasing etas", () => {
    const plan = parseTrajectory(gps, [
      { coordinates: { latitude: "44.70", longitude: "20.60" }, second_left_by_route: 0 }, // passed
      { coordinates: { latitude: "44.71", longitude: "20.61" }, second_left_by_route: 0 }, // passed
      { coordinates: { latitude: "44.80", longitude: "20.53" }, second_left_by_route: 50 }, // ahead
      { coordinates: { latitude: "44.80", longitude: "20.53" }, second_left_by_route: 50 }, // dup eta — drop
      { coordinates: { latitude: "44.81", longitude: "20.52" }, second_left_by_route: 90 },
    ]);
    expect(plan).toEqual([
      { lat: 44.79, lon: 20.54, etaSeconds: 0 },
      { lat: 44.8, lon: 20.53, etaSeconds: 50 },
      { lat: 44.81, lon: 20.52, etaSeconds: 90 },
    ]);
  });

  it("returns null when nothing is ahead of the vehicle", () => {
    expect(
      parseTrajectory(gps, [
        { coordinates: { latitude: "44.70", longitude: "20.60" }, second_left_by_route: 0 },
      ]),
    ).toBeNull();
  });

  it("returns null when all_stations is missing or not an array", () => {
    expect(parseTrajectory(gps, undefined)).toBeNull();
    expect(parseTrajectory(gps, "nope")).toBeNull();
    expect(parseTrajectory(gps, [])).toBeNull();
  });

  it("ignores entries with unparseable coordinates or eta", () => {
    const plan = parseTrajectory(gps, [
      { coordinates: { latitude: "nan", longitude: "20.53" }, second_left_by_route: 40 },
      { coordinates: { latitude: "44.80", longitude: "20.53" }, second_left_by_route: "60" }, // eta not a number
      { coordinates: { latitude: "44.81", longitude: "20.52" }, second_left_by_route: 80 },
    ]);
    expect(plan).toEqual([
      { lat: 44.79, lon: 20.54, etaSeconds: 0 },
      { lat: 44.81, lon: 20.52, etaSeconds: 80 },
    ]);
  });
});
