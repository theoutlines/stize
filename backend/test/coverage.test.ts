import { describe, expect, it } from "vitest";
import { accumulateSegments, buildCoverage, buildCoveragePoints } from "../scripts/coverage-core.mjs";

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

  it("emits real-point centroids, not grid-cell centres (anti-staircase)", () => {
    // A point offset well inside its cell: cell centre would be (44.800, 20.400),
    // but the output must be the real point since it's the only one in the cell.
    const gj = buildCoverage(
      [
        {
          line: "1",
          vehicleType: "bus",
          polyline: [
            [44.80042, 20.40042],
            [44.80142, 20.40142],
          ],
        },
      ],
      { grid: 0.001, simplifyEpsilon: 0, coordPrecision: 5 },
    );
    const [lon, lat] = gj.features[0].geometry.coordinates[0];
    expect(lat).toBeCloseTo(44.80042, 5); // real coord, not 44.800 cell centre
    expect(lon).toBeCloseTo(20.40042, 5);
  });

  it("keeps two routes' shared corridor coincident after smoothing", () => {
    // Two routes with slightly different real geometry that snaps to the same
    // cells must still produce identical (centroid) coordinates — no doubling.
    const a = [
      [44.8001, 20.4001],
      [44.8011, 20.4011],
    ];
    const b = [
      [44.8003, 20.4003],
      [44.8013, 20.4013],
    ];
    const gj = buildCoverage(
      [
        { line: "2", vehicleType: "tram", polyline: a },
        { line: "5", vehicleType: "tram", polyline: b },
      ],
      { grid: 0.001, simplifyEpsilon: 0 },
    );
    // One shared corridor (routes_count 2), single feature.
    expect(gj.features).toHaveLength(1);
    expect(gj.features[0].properties.routes_count).toBe(2);
    // Its coords are the per-cell centroid of both routes' points.
    const [lon, lat] = gj.features[0].geometry.coordinates[0];
    expect(lat).toBeCloseTo((44.8001 + 44.8003) / 2, 5);
    expect(lon).toBeCloseTo((20.4001 + 20.4003) / 2, 5);
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

describe("buildCoveragePoints (render layer: heatmap points)", () => {
  // ~0.001° of longitude at 44.8° ≈ 79 m; a west→east run one step long.
  const eastRun = (n: number) => {
    const pts: number[][] = [];
    for (let i = 0; i <= n; i++) pts.push([44.8, 20.4 + i * 0.001]);
    return pts;
  };

  it("emits Point features spaced ~stepMetres apart, tagged by type", () => {
    // ~790 m run, 100 m step → ~8-9 points.
    const gj = buildCoveragePoints([{ line: "25", vehicleType: "bus", polyline: eastRun(10) }], {
      stepMetres: 100,
    });
    expect(gj.type).toBe("FeatureCollection");
    expect(gj.features.length).toBeGreaterThanOrEqual(7);
    expect(gj.features.length).toBeLessThanOrEqual(10);
    for (const f of gj.features) {
      expect(f.geometry.type).toBe("Point");
      expect(f.properties).toEqual({ type: "bus" });
    }
    // First sample sits at the polyline start, coords as [lon, lat].
    expect(gj.features[0].geometry.coordinates[0]).toBeCloseTo(20.4, 5);
    expect(gj.features[0].geometry.coordinates[1]).toBeCloseTo(44.8, 5);
  });

  it("finer spacing yields more points (density scales with sampling)", () => {
    const coarse = buildCoveragePoints([{ line: "1", vehicleType: "bus", polyline: eastRun(20) }], {
      stepMetres: 150,
    });
    const fine = buildCoveragePoints([{ line: "1", vehicleType: "bus", polyline: eastRun(20) }], {
      stepMetres: 50,
    });
    expect(fine.features.length).toBeGreaterThan(coarse.features.length);
  });

  it("overlapping routes stack their points (density = overlap)", () => {
    const one = buildCoveragePoints([{ line: "2", vehicleType: "tram", polyline: eastRun(10) }], {
      stepMetres: 100,
    });
    const two = buildCoveragePoints(
      [
        { line: "2", vehicleType: "tram", polyline: eastRun(10) },
        { line: "5", vehicleType: "tram", polyline: eastRun(10) },
      ],
      { stepMetres: 100 },
    );
    // Two routes over the same corridor produce ~twice the points there.
    expect(two.features.length).toBeCloseTo(one.features.length * 2, -1);
  });

  it("carries the vehicle type for the heatmap's per-type filter", () => {
    const gj = buildCoveragePoints(
      [
        { line: "2", vehicleType: "tram", polyline: eastRun(3) },
        { line: "28", vehicleType: "trolleybus", polyline: eastRun(3) },
      ],
      { stepMetres: 100 },
    );
    const types = new Set(gj.features.map((f: any) => f.properties.type));
    expect([...types].sort()).toEqual(["tram", "trolleybus"]);
  });

  it("skips shapes with fewer than two points", () => {
    const gj = buildCoveragePoints([
      { line: "1", vehicleType: "bus", polyline: [[44.8, 20.4]] },
      { line: "2", vehicleType: "bus", polyline: [] },
    ]);
    expect(gj.features).toHaveLength(0);
  });
});
