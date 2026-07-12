// Types for the I/O-free coverage build core (coverage-core.mjs), so the
// backend TS test (test/coverage.test.ts) can import it type-checked.

export const DEFAULT_GRID_DEG: number;

export interface CoverageShape {
  line: string;
  vehicleType: string;
  /** Points as [lat, lon]. */
  polyline: number[][];
}

export interface CoverageSegment {
  a: number[];
  b: number[];
  lines: Set<string>;
  types: Set<string>;
}

export interface CoverageFeature {
  type: "Feature";
  properties: { routes_count: number; types: string[] };
  geometry: { type: "LineString"; coordinates: number[][] };
}

export interface CoverageFeatureCollection {
  type: "FeatureCollection";
  features: CoverageFeature[];
}

export interface BuildCoverageOptions {
  grid?: number;
  simplifyEpsilon?: number;
  coordPrecision?: number;
}

export function accumulateSegments(
  shapes: CoverageShape[],
  grid?: number,
): Map<string, CoverageSegment>;

export function buildCoverage(
  shapes: CoverageShape[],
  opts?: BuildCoverageOptions,
): CoverageFeatureCollection;

export interface CoverageLineFeature {
  type: "Feature";
  properties: { type: string; line: string };
  geometry: { type: "LineString"; coordinates: number[][] };
}

export interface CoverageLineFeatureCollection {
  type: "FeatureCollection";
  features: CoverageLineFeature[];
}

export function buildCoverageLines(
  shapes: CoverageShape[],
  opts?: { simplifyEpsilon?: number; coordPrecision?: number },
): CoverageLineFeatureCollection;
