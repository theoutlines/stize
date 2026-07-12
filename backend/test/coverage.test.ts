import { describe, expect, it } from "vitest";
import { accumulateSegments, buildCoverage } from "../scripts/coverage-core.mjs";

// A straight west→east run of points along one latitude, spaced ~1 grid cell
// apart at grid=0.001 so each pair lands in a distinct cell.
function horizontalLine(lat: number, lonStart: number, steps: number): number[][] {
  const pts: number[][] = [];
  for (let i = 0; i <= steps; i++) pts.push([lat, lonStart + i * 0.001]);
  return pts;
}

const GRID = 0.001;

describe("coverage-core", () => {
  it("counts a single line's own segment as routes_count 1", () => {
    const shapes = [{ line: "25", vehicleType: "bus", polyline: horizontalLine(44.8, 20.4, 3) }];
    const gj = buildCoverage(shapes, { grid: GRID, simplifyEpsilon: 0 });
    expect(gj.type).toBe("FeatureCollection");
    // One line, unshared → collapses into a single feature.
    expect(gj.features).toHaveLength(1);
    expect(gj.features[0].properties.routes_count).toBe(1);
    expect(gj.features[0].properties.types).toEqual(["bus"]);
    expect(gj.features[0].geometry.type).toBe("LineString");
  });

  it("collapses a segment shared by two routes and counts both", () => {
    // Two lines run the exact same geometry.
    const geom = horizontalLine(44.8, 20.4, 2);
    const shapes = [
      { line: "2", vehicleType: "tram", polyline: geom },
      { line: "5", vehicleType: "tram", polyline: geom },
    ];
    const segs = accumulateSegments(shapes, GRID);
    // 2 point-pairs → 2 undirected segments, each carrying both lines.
    expect(segs.size).toBe(2);
    for (const seg of segs.values()) {
      expect(seg.lines.size).toBe(2);
    }
    const gj = buildCoverage(shapes, { grid: GRID, simplifyEpsilon: 0 });
    expect(gj.features.every((f: any) => f.properties.routes_count === 2)).toBe(true);
  });

  it("collapses opposite directions of the same geometry (undirected)", () => {
    const geom = horizontalLine(44.8, 20.4, 2);
    const reversed = [...geom].reverse();
    const segs = accumulateSegments(
      [
        { line: "7", vehicleType: "bus", polyline: geom },
        { line: "7", vehicleType: "bus", polyline: reversed },
      ],
      GRID,
    );
    // A→B and B→A must map to the same segment key, and the same line counts once.
    expect(segs.size).toBe(2);
    for (const seg of segs.values()) {
      expect(seg.lines.size).toBe(1);
      expect([...seg.lines]).toEqual(["7"]);
    }
  });

  it("merges the distinct vehicle types on a shared segment, ordered", () => {
    const geom = horizontalLine(44.8, 20.4, 1);
    const gj = buildCoverage(
      [
        { line: "3", vehicleType: "bus", polyline: geom },
        { line: "2", vehicleType: "tram", polyline: geom },
        { line: "28", vehicleType: "trolleybus", polyline: geom },
      ],
      { grid: GRID, simplifyEpsilon: 0 },
    );
    // Single shared segment, all three types present, in tram→trolley→bus order.
    expect(gj.features).toHaveLength(1);
    expect(gj.features[0].properties.routes_count).toBe(3);
    expect(gj.features[0].properties.types).toEqual(["tram", "trolleybus", "bus"]);
  });

  it("splits a line into weighted pieces where a second line joins and leaves", () => {
    // Line A runs the whole way; line B shares only the middle cell.
    const a = { line: "A", vehicleType: "bus", polyline: horizontalLine(44.8, 20.4, 3) };
    const b = { line: "B", vehicleType: "bus", polyline: horizontalLine(44.8, 20.401, 1) };
    const gj = buildCoverage([a, b], { grid: GRID, simplifyEpsilon: 0 });
    const counts = gj.features.map((f: any) => f.properties.routes_count).sort();
    // Some segment(s) are shared (count 2), the rest are A alone (count 1).
    expect(counts).toContain(2);
    expect(counts).toContain(1);
  });

  it("ignores shapes with fewer than two points", () => {
    const gj = buildCoverage(
      [
        { line: "1", vehicleType: "bus", polyline: [[44.8, 20.4]] },
        { line: "2", vehicleType: "bus", polyline: [] },
      ],
      { grid: GRID },
    );
    expect(gj.features).toHaveLength(0);
  });

  it("emits GeoJSON coordinates as [lon, lat]", () => {
    const gj = buildCoverage(
      [{ line: "9", vehicleType: "tram", polyline: horizontalLine(44.8, 20.4, 1) }],
      { grid: GRID, simplifyEpsilon: 0 },
    );
    const [lon, lat] = gj.features[0].geometry.coordinates[0];
    expect(lon).toBeCloseTo(20.4, 2);
    expect(lat).toBeCloseTo(44.8, 2);
  });
});
