import { describe, expect, it } from "vitest";
import { accumulateSegments, buildCoverage, buildCoverageLines } from "../scripts/coverage-core.mjs";

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

describe("buildCoverageLines (render layer: raw shapes)", () => {
  it("keeps one feature per shape with raw geometry and type/line props", () => {
    const poly = [
      [44.8, 20.4],
      [44.801, 20.402],
      [44.803, 20.401],
    ];
    const gj = buildCoverageLines([
      { line: "25", vehicleType: "bus", polyline: poly },
    ]);
    expect(gj.type).toBe("FeatureCollection");
    expect(gj.features).toHaveLength(1);
    const f = gj.features[0];
    expect(f.properties).toEqual({ type: "bus", line: "25" });
    // Raw geometry preserved (no collapsing/snapping), as [lon, lat].
    expect(f.geometry.coordinates).toEqual([
      [20.4, 44.8],
      [20.402, 44.801],
      [20.401, 44.803],
    ]);
  });

  it("does NOT collapse overlapping routes — one feature each", () => {
    const geom = [
      [44.8, 20.4],
      [44.81, 20.41],
    ];
    const gj = buildCoverageLines([
      { line: "2", vehicleType: "tram", polyline: geom },
      { line: "5", vehicleType: "tram", polyline: geom },
    ]);
    // Overlap is drawn by stacking, not merged — both features are kept.
    expect(gj.features).toHaveLength(2);
  });

  it("skips shapes with fewer than two points", () => {
    const gj = buildCoverageLines([
      { line: "1", vehicleType: "bus", polyline: [[44.8, 20.4]] },
      { line: "2", vehicleType: "bus", polyline: [] },
    ]);
    expect(gj.features).toHaveLength(0);
  });

  it("simplifies only when asked, preserving endpoints", () => {
    // A near-straight line with a tiny mid jog; a small epsilon drops the jog.
    const poly = [
      [44.8, 20.4],
      [44.8000001, 20.4005],
      [44.8, 20.401],
    ];
    const gj = buildCoverageLines([{ line: "1", vehicleType: "bus", polyline: poly }], {
      simplifyEpsilon: 0.00002,
    });
    const coords = gj.features[0].geometry.coordinates;
    expect(coords).toHaveLength(2); // mid point removed
    expect(coords[0]).toEqual([20.4, 44.8]);
    expect(coords[1]).toEqual([20.401, 44.8]);
  });
});
