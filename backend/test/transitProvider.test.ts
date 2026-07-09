import { describe, expect, it } from "vitest";
import { headingFromRoute, parseRawArrival } from "../src/lib/transitProvider";

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
    });
  });

  it("treats a non-numeric gps payload as absent", () => {
    const result = parseRawArrival({ line_number: "5", vehicles: [{ lat: null, lng: null }] });
    expect(result.gps).toBeNull();
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

  it("returns null with fewer than two stations", () => {
    expect(headingFromRoute({ lat: 44.8, lon: 20.5 }, [])).toBeNull();
    expect(headingFromRoute({ lat: 44.8, lon: 20.5 }, [{ lat: 44.8, lon: 20.5 }])).toBeNull();
  });
});
