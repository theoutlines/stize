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

export interface CoveragePointFeature {
  type: "Feature";
  properties: { type: string };
  geometry: { type: "Point"; coordinates: number[] };
}

export interface CoveragePointFeatureCollection {
  type: "FeatureCollection";
  features: CoveragePointFeature[];
}

export function buildCoveragePoints(
  shapes: CoverageShape[],
  opts?: { stepMetres?: number; coordPrecision?: number },
): CoveragePointFeatureCollection;

export interface CoverageFlowShape {
  routeId: string;
  vehicleType: string;
  tripsPerDay: number;
  polyline: number[][];
}

export interface CoverageFlowFeature {
  type: "Feature";
  properties: { type: string; trips: number };
  geometry: { type: "LineString"; coordinates: number[][] };
}

export function buildCoverageFlow(
  shapes: CoverageFlowShape[],
  opts?: { grid?: number; smoothPasses?: number; simplifyEpsilon?: number; reach?: number; coordPrecision?: number },
): { type: "FeatureCollection"; features: CoverageFlowFeature[] };

export function buildCoverageGlow(
  shapes: { vehicleType: string; tripsPerDay: number; polyline: number[][] }[],
  opts?: { stepMetres?: number; coordPrecision?: number },
): {
  type: "FeatureCollection";
  features: {
    type: "Feature";
    properties: { type: string; trips: number };
    geometry: { type: "MultiPoint"; coordinates: number[][] };
  }[];
};
