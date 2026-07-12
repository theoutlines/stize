// Pure, I/O-free core of the coverage-map build (see build-coverage.mjs for the
// file-reading runner). Kept separate so the collapsing/counting logic can be
// unit-tested in the Workers vitest pool without touching node:fs.
//
// The job: turn every route's shape geometry into a single set of line
// segments where segments shared by several routes are collapsed into one,
// carrying how many distinct lines run along them and which vehicle types.
// The result is a precomputed GeoJSON the client renders as a static "coverage"
// layer (data-driven width/brightness by weight) — no per-frame work.

// Grid cell used to decide when two points from different shapes are "the same
// place" (segment collapsing tolerance). At Belgrade's latitude (~44.8°),
// 0.0005° ≈ 55 m north-south, ≈ 40 m east-west — coarse enough to merge the two
// carriageways of a boulevard and digitisation offsets between routes' shapes
// into one clean corridor (no doubled lines), without fusing genuinely separate
// parallel streets. It also keeps the precomputed file light (~2.7 MB raw /
// ~180 KB gzip city-wide). The grid is used only for segment *identity*; the
// output geometry uses each cell's real-point centroid (see accumulate), so the
// cell size no longer causes "staircase" blockiness — a coarser grid just merges
// more aggressively, a finer one keeps more distinct corridors (bigger file).
export const DEFAULT_GRID_DEG = 0.0005;

// Stable output order for the `types` array so the file is reproducible.
const TYPE_ORDER = ["tram", "trolleybus", "bus"];

function snap(lat, lon, grid) {
  // Integer grid indices [iy, ix]; identical indices ⇒ same grid cell.
  return [Math.round(lat / grid), Math.round(lon / grid)];
}

const nodeKey = (n) => `${n[0]},${n[1]}`;

// Undirected segment key: a segment traversed A→B by one route and B→A by
// another (e.g. opposite directions of a line) must collapse to one.
function segmentKey(ka, kb) {
  return ka < kb ? `${ka}|${kb}` : `${kb}|${ka}`;
}

function sortTypes(types) {
  return [...types].sort((a, b) => TYPE_ORDER.indexOf(a) - TYPE_ORDER.indexOf(b));
}

/**
 * Accumulate shared segments from all shapes.
 *
 * @param {Array<{line:string, vehicleType:string, polyline:number[][]}>} shapes
 *   polyline points are [lat, lon] (as stored in public/gtfs/shapes/*.json).
 * @param {number} grid grid cell size in degrees.
 * @returns {Map<string,{a:number[],b:number[],lines:Set<string>,types:Set<string>}>}
 */
export function accumulateSegments(shapes, grid = DEFAULT_GRID_DEG) {
  return accumulate(shapes, grid).segments;
}

/**
 * Core pass: builds the shared-segment map *and* a per-grid-node centroid of the
 * real (unsnapped) points that fell in each cell.
 *
 * The centroid is what kills the "staircase": we snap to the grid only to decide
 * segment *identity* (so shared corridors collapse), but the output geometry uses
 * each node's centroid — which lies on the actual road, not at the grid-lattice
 * cell centre. All routes through a cell share the same centroid, so shared
 * corridors still coincide exactly (no doubling) while diagonal roads render as
 * smooth diagonals instead of right-angle jogs.
 *
 * @returns {{segments: Map, nodeCoord: Map<string, number[]>}} nodeCoord maps a
 *   node key to its centroid [lat, lon].
 */
function accumulate(shapes, grid) {
  const segments = new Map();
  const nodeSum = new Map(); // nodeKey -> [sumLat, sumLon, count]
  const addPoint = (key, lat, lon) => {
    const s = nodeSum.get(key);
    if (s) {
      s[0] += lat;
      s[1] += lon;
      s[2] += 1;
    } else {
      nodeSum.set(key, [lat, lon, 1]);
    }
  };

  for (const shape of shapes) {
    const poly = shape.polyline;
    if (!Array.isArray(poly) || poly.length < 2) continue;
    let prev = null;
    let prevKey = null;
    for (const point of poly) {
      const [lat, lon] = point;
      const node = snap(lat, lon, grid);
      const key = nodeKey(node);
      addPoint(key, lat, lon); // feed the centroid, duplicates in a cell included
      if (prevKey === null) {
        prev = node;
        prevKey = key;
        continue;
      }
      if (key === prevKey) continue; // stayed inside the same cell
      const sk = segmentKey(prevKey, key);
      let seg = segments.get(sk);
      if (!seg) {
        seg = { a: prev, b: node, lines: new Set(), types: new Set() };
        segments.set(sk, seg);
      }
      seg.lines.add(shape.line);
      seg.types.add(shape.vehicleType);
      prev = node;
      prevKey = key;
    }
  }

  const nodeCoord = new Map();
  for (const [key, [sumLat, sumLon, count]] of nodeSum) {
    nodeCoord.set(key, [sumLat / count, sumLon / count]);
  }
  return { segments, nodeCoord };
}

// Signature groups segments that carry the *same* set of lines, so they can be
// merged into one polyline (they'll get identical properties). Two segments
// with the same line set always have the same type set and routes_count too.
function signatureOf(seg) {
  return [...seg.lines].sort().join(",");
}

/**
 * Chain a group's undirected edges into as few polylines as possible. Greedy
 * edge-walk: good enough for a static build (no need for a strictly minimal
 * cover), and it turns a line's own unshared run back into a single feature.
 *
 * @param {Array<{a:number[],b:number[]}>} edges
 * @returns {number[][][]} polylines as arrays of [iy, ix] grid nodes.
 */
function chainEdges(edges) {
  // Adjacency over grid nodes; each edge listed from both endpoints.
  const adj = new Map(); // nodeKey -> Array<{ to:node, toKey, edgeId }>
  const coord = new Map(); // nodeKey -> node
  const used = new Set(); // edgeId
  const add = (fromKey, from, to, toKey, edgeId) => {
    coord.set(fromKey, from);
    if (!adj.has(fromKey)) adj.set(fromKey, []);
    adj.get(fromKey).push({ to, toKey, edgeId });
  };
  edges.forEach((e, i) => {
    const ka = nodeKey(e.a);
    const kb = nodeKey(e.b);
    add(ka, e.a, e.b, kb, i);
    add(kb, e.b, e.a, ka, i);
  });

  const nextUnused = (key) => (adj.get(key) ?? []).find((n) => !used.has(n.edgeId));

  const polylines = [];
  // Start walks from degree-1 nodes first (open path ends) for longer chains,
  // then mop up any remaining loops from any node.
  const starts = [...adj.keys()].sort((a, b) => adj.get(a).length - adj.get(b).length);
  for (const start of starts) {
    let curKey = start;
    let cur = coord.get(start);
    let edge = nextUnused(curKey);
    if (!edge) continue;
    const path = [cur];
    while (edge) {
      used.add(edge.edgeId);
      path.push(edge.to);
      curKey = edge.toKey;
      cur = edge.to;
      edge = nextUnused(curKey);
    }
    if (path.length >= 2) polylines.push(path);
  }
  return polylines;
}

// Perpendicular-distance simplification (Ramer–Douglas–Peucker), dropping
// near-collinear midpoints so straight runs don't carry a vertex per grid cell.
// Points are [lat, lon] and epsilon is in degrees.
function simplify(points, epsilon) {
  if (points.length <= 2 || epsilon <= 0) return points;
  let maxDist = 0;
  let index = 0;
  const [ax, ay] = [points[0][0], points[0][1]];
  const [bx, by] = [points[points.length - 1][0], points[points.length - 1][1]];
  const dx = bx - ax;
  const dy = by - ay;
  const len = Math.hypot(dx, dy) || 1;
  for (let i = 1; i < points.length - 1; i++) {
    const [px, py] = points[i];
    const dist = Math.abs((px - ax) * dy - (py - ay) * dx) / len;
    if (dist > maxDist) {
      maxDist = dist;
      index = i;
    }
  }
  if (maxDist <= epsilon) return [points[0], points[points.length - 1]];
  const left = simplify(points.slice(0, index + 1), epsilon);
  const right = simplify(points.slice(index), epsilon);
  return [...left.slice(0, -1), ...right];
}

/**
 * Build the coverage GeoJSON FeatureCollection from all route shapes.
 *
 * Properties per feature (with headroom for future weightings, per the spec —
 * the client reads its weight from a single named property so adding a
 * frequency- or intensity-based weight later doesn't break it):
 *   routes_count: number of distinct lines along the segment (V0 weight)
 *   types:        distinct vehicle types, ordered tram → trolleybus → bus
 *
 * @param {Array<{line:string, vehicleType:string, polyline:number[][]}>} shapes
 * @param {{grid?:number, simplifyEpsilon?:number, coordPrecision?:number}} opts
 */
export function buildCoverage(shapes, opts = {}) {
  const grid = opts.grid ?? DEFAULT_GRID_DEG;
  // Default epsilon ~0.4 cell in degrees: trims collinear midpoints without
  // visibly moving the smoothed (centroid) geometry.
  const simplifyEpsilon = opts.simplifyEpsilon ?? grid * 0.4;
  const coordPrecision = opts.coordPrecision ?? 5;

  const { segments, nodeCoord } = accumulate(shapes, grid);

  // Group segments by their line-set signature.
  const groups = new Map(); // signature -> { edges:[], lines:Set, types:Set }
  for (const seg of segments.values()) {
    const sig = signatureOf(seg);
    let group = groups.get(sig);
    if (!group) {
      group = { edges: [], lines: seg.lines, types: seg.types };
      groups.set(sig, group);
    }
    group.edges.push({ a: seg.a, b: seg.b });
  }

  const round = (v) => Number(v.toFixed(coordPrecision));
  const features = [];
  for (const group of groups.values()) {
    const routesCount = group.lines.size;
    const types = sortTypes(group.types);
    for (const chain of chainEdges(group.edges)) {
      // Grid nodes [iy, ix] → their real-point centroid [lat, lon] (smooth,
      // on-road geometry), then simplify in degree space.
      const latLon = chain.map((node) => nodeCoord.get(nodeKey(node)));
      const simplified = simplify(latLon, simplifyEpsilon);
      // [lat, lon] → GeoJSON [lon, lat].
      const coordinates = simplified.map(([lat, lon]) => [round(lon), round(lat)]);
      features.push({
        type: "Feature",
        properties: { routes_count: routesCount, types },
        geometry: { type: "LineString", coordinates },
      });
    }
  }

  // Sort features by weight so the densest corridors are drawn last (on top).
  features.sort((a, b) => a.properties.routes_count - b.properties.routes_count);

  return { type: "FeatureCollection", features };
}

/**
 * Build the *render* GeoJSON: the raw route shapes as-is (one LineString per
 * route direction), no segment collapsing, no grid snapping. The client draws
 * these as many semi-transparent lines so overlapping routes accumulate
 * brightness — a Strava-heatmap-style density map where corridors bleed into
 * glow zones at far zoom. Keeping the real geometry also means zero staircase.
 *
 * Only geometry-preserving simplification is applied (small epsilon), purely to
 * keep the file light; it must not change the visible shape.
 *
 * Properties per feature:
 *   type: vehicle type (tram/trolleybus/bus) — drives the type filter + colour
 *   line: line number — carried for future use (not required by the renderer)
 *
 * @param {Array<{line:string, vehicleType:string, polyline:number[][]}>} shapes
 * @param {{simplifyEpsilon?:number, coordPrecision?:number}} opts
 */
export function buildCoverageLines(shapes, opts = {}) {
  const simplifyEpsilon = opts.simplifyEpsilon ?? 0;
  const coordPrecision = opts.coordPrecision ?? 5;
  const round = (v) => Number(v.toFixed(coordPrecision));

  const features = [];
  for (const shape of shapes) {
    const poly = shape.polyline;
    if (!Array.isArray(poly) || poly.length < 2) continue;
    const simplified = simplifyEpsilon > 0 ? simplify(poly, simplifyEpsilon) : poly;
    if (simplified.length < 2) continue;
    // Source polyline is [lat, lon] → GeoJSON [lon, lat].
    const coordinates = simplified.map(([lat, lon]) => [round(lon), round(lat)]);
    features.push({
      type: "Feature",
      properties: { type: shape.vehicleType, line: shape.line },
      geometry: { type: "LineString", coordinates },
    });
  }
  return { type: "FeatureCollection", features };
}
