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

// Metres per degree of latitude (roughly constant). Longitude is scaled by
// cos(lat) at Belgrade's latitude. Good enough for ~tens-of-metres resampling.
const M_PER_DEG_LAT = 110540;
const metresPerDegLon = (lat) => 111320 * Math.cos((lat * Math.PI) / 180);

// Planar distance in metres between two [lat, lon] points (equirectangular).
function metresBetween(a, b) {
  const latMid = (a[0] + b[0]) / 2;
  const dx = (b[1] - a[1]) * metresPerDegLon(latMid);
  const dy = (b[0] - a[0]) * M_PER_DEG_LAT;
  return Math.hypot(dx, dy);
}

/**
 * Resample a [lat, lon] polyline to a point roughly every `stepMetres` along its
 * length (plus the first vertex), interpolating within segments. Returns
 * [lat, lon] points.
 */
function resample(poly, stepMetres) {
  const out = [poly[0]];
  let prev = poly[0];
  let need = stepMetres; // distance remaining until the next emitted point
  for (let i = 1; i < poly.length; i++) {
    const cur = poly[i];
    let seg = metresBetween(prev, cur);
    while (seg >= need && seg > 0) {
      const t = need / seg;
      const np = [prev[0] + (cur[0] - prev[0]) * t, prev[1] + (cur[1] - prev[1]) * t];
      out.push(np);
      prev = np;
      seg = metresBetween(prev, cur);
      need = stepMetres;
    }
    need -= seg;
    prev = cur;
  }
  return out;
}

/**
 * Build the *render* GeoJSON for the heatmap: every route's shape resampled to
 * evenly-spaced points. Each route contributes its own points, so where routes
 * overlap the local point density is higher — which a MapLibre heatmap layer
 * turns into brightness (Strava-global-heatmap style). No separate route
 * counting is needed; density *is* the weight.
 *
 * Emits one Point feature per sample (the canonical, guaranteed heatmap input),
 * each carrying its `type` so the type filter works on the same layer.
 *
 * @param {Array<{line:string, vehicleType:string, polyline:number[][]}>} shapes
 * @param {{stepMetres?:number, coordPrecision?:number}} opts
 */
export function buildCoveragePoints(shapes, opts = {}) {
  const stepMetres = opts.stepMetres ?? 90;
  const coordPrecision = opts.coordPrecision ?? 5;
  const round = (v) => Number(v.toFixed(coordPrecision));

  const features = [];
  for (const shape of shapes) {
    const poly = shape.polyline;
    if (!Array.isArray(poly) || poly.length < 2) continue;
    const type = shape.vehicleType;
    for (const [lat, lon] of resample(poly, stepMetres)) {
      features.push({
        type: "Feature",
        properties: { type },
        geometry: { type: "Point", coordinates: [round(lon), round(lat)] },
      });
    }
  }
  return { type: "FeatureCollection", features };
}

// Trips round down to these steps (~1.3× apart), so a street with slightly
// different counts along it stays one piece.
const TRIP_STEPS = [1, 5, 10, 15, 20, 25, 35, 50, 65, 85, 110, 150, 200, 260, 340, 450, 600, 800, 1050, 1400, 1850, 2400, 3150, 4100];
function bucketTrips(n) {
  let out = TRIP_STEPS[0];
  for (const step of TRIP_STEPS) if (n >= step) out = step;
  return out;
}

/**
 * Build coverage mode's *flow lines* the way transit frequency maps do it:
 * by stop-to-stop segments. Every route direction is cut at its stops; a
 * segment's identity is the pair of stations it runs between (a station is a
 * stop name at one place, so both directions' stops across the street count
 * as one). Routes serving the same pair share that segment exactly, so there
 * is no geometric guesswork: each segment is drawn once, from the busiest
 * route's own shape, and carries `trips`, the weekday trips of every route
 * direction of that type between those two stations. Segment ends are pinned
 * to the station, so segments meet exactly and run on as one line; the width
 * changes only at a stop.
 *
 * @param {Array<{routeId:string, vehicleType:string, tripsPerDay:number,
 *   polyline:number[][], stops:Array<{stop_id:string,name:string,lat:number,lon:number}>}>} shapes
 * @param {{simplifyEpsilon?:number, coordPrecision?:number}} opts
 */
export function buildCoverageFlow(shapes, opts = {}) {
  const simplifyEpsilon = opts.simplifyEpsilon ?? 0.00003; // ~3 m
  const coordPrecision = opts.coordPrecision ?? 5;
  const stationMetres = opts.stationMetres ?? 150;
  const passMetres = opts.passMetres ?? 25;
  const round = (v) => Number(v.toFixed(coordPrecision));
  // A station: stops sharing a name (platform number dropped) within
  // `stationMetres` of each other, e.g. both sides of the street.
  const baseName = (st) => String(st.name ?? st.stop_id).replace(/\s+\d+$/, "").trim();
  const stations = []; // { name, lat, lon, n }
  const stationIdOf = new Map(); // stop_id -> station index
  for (const sh of shapes) {
    for (const st of sh.stops ?? []) {
      if (stationIdOf.has(st.stop_id)) continue;
      const name = baseName(st);
      let i = stations.findIndex(
        (x) => x.name === name && metresBetween([x.lat, x.lon], [st.lat, st.lon]) < stationMetres,
      );
      if (i < 0) {
        stations.push({ name, lat: st.lat, lon: st.lon, n: 1 });
        i = stations.length - 1;
      } else {
        const x = stations[i];
        x.lat = (x.lat * x.n + st.lat) / (x.n + 1);
        x.lon = (x.lon * x.n + st.lon) / (x.n + 1);
        x.n += 1;
      }
      stationIdOf.set(st.stop_id, i);
    }
  }
  const at = (i) => [stations[i].lat, stations[i].lon];
  // Stations by ~200 m cell, to find the ones a route passes without stopping.
  const cellKey = (lat, lon) => `${Math.round(lat / 0.002)},${Math.round(lon / 0.0028)}`;
  const byCell = new Map();
  stations.forEach((x, i) => {
    const k = cellKey(x.lat, x.lon);
    if (!byCell.has(k)) byCell.set(k, []);
    byCell.get(k).push(i);
  });
  const stationsNear = (pt) => {
    const [cy, cx] = cellKey(pt[0], pt[1]).split(",").map(Number);
    const out = [];
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) out.push(...(byCell.get(`${cy + dy},${cx + dx}`) ?? []));
    return out;
  };
  // Index of the polyline point nearest to a stop, searching forward.
  const nearest = (poly, st, from) => {
    let best = from;
    let bestD = Infinity;
    for (let i = from; i < poly.length; i++) {
      const d = metresBetween(poly[i], [st.lat, st.lon]);
      if (d < bestD) (bestD = d), (best = i);
    }
    return best;
  };
  // A route's stations in order: the ones it stops at, plus the ones it
  // passes within `passMetres` of without stopping (express runs), so a
  // street is cut at the same stations for every route along it.
  const stationsAlong = (s) => {
    const seq = [];
    let from = 0;
    const stopAt = new Map();
    for (const st of s.stops) {
      const idx = nearest(s.polyline, st, from);
      stopAt.set(idx, stationIdOf.get(st.stop_id));
      from = idx;
    }
    for (let i = 0; i < s.polyline.length; i++) {
      if (stopAt.has(i)) {
        seq.push({ k: stopAt.get(i), idx: i });
        continue;
      }
      for (const k of stationsNear(s.polyline[i])) {
        if (metresBetween(s.polyline[i], at(k)) < passMetres) {
          seq.push({ k, idx: i });
          break;
        }
      }
    }
    // Collapse repeats (a station spans several points).
    return seq.filter((x, j) => j === 0 || x.k !== seq[j - 1].k);
  };

  const features = [];
  for (const type of TYPE_ORDER) {
    const ofType = shapes
      .filter((s) => s.vehicleType === type && (s.tripsPerDay ?? 0) > 0)
      .filter((s) => Array.isArray(s.polyline) && s.polyline.length >= 2 && (s.stops?.length ?? 0) >= 2)
      .sort((a, b) => b.tripsPerDay - a.tripsPerDay);
    const segs = new Map(); // undirected station pair -> { trips, a, b, points }
    for (const s of ofType) {
      let prev = null;
      for (const cur of stationsAlong(s)) {
        if (prev) {
          const key = prev.k < cur.k ? `${prev.k}~${cur.k}` : `${cur.k}~${prev.k}`;
          let seg = segs.get(key);
          if (!seg) {
            // The busiest route lends its geometry (routes come busiest first).
            seg = { trips: 0, a: prev.k, b: cur.k, points: s.polyline.slice(prev.idx, cur.idx + 1) };
            segs.set(key, seg);
          }
          seg.trips += s.tripsPerDay;
        }
        prev = cur;
      }
    }
    for (const seg of segs.values()) {
      // Pin the ends to the stations, so neighbouring segments meet exactly.
      const pts = [at(seg.a), ...seg.points.slice(1, -1), at(seg.b)];
      features.push({
        type: "Feature",
        properties: { type, trips: bucketTrips(seg.trips) },
        geometry: {
          type: "LineString",
          coordinates: simplify(pts, simplifyEpsilon).map(([lat, lon]) => [round(lon), round(lat)]),
        },
      });
    }
  }
  features.sort((a, b) => a.properties.trips - b.properties.trips);
  return { type: "FeatureCollection", features };
}

/**
 * Build coverage mode's *glow points*: every city route resampled every
 * `stepMetres`, one MultiPoint per route carrying its `type` and own weekday
 * `trips`. The client draws them as a narrow heatmap under the strokes: where
 * routes share a street their points pile up and the glow brightens, but only
 * within the heatmap's radius and up to the top of its colour ramp, so it
 * accumulates without blooming over the block.
 *
 * @param {Array<{vehicleType:string, tripsPerDay:number, polyline:number[][]}>} shapes
 * @param {{stepMetres?:number, coordPrecision?:number}} opts
 */
export function buildCoverageGlow(shapes, opts = {}) {
  const step = opts.stepMetres ?? 25;
  const precision = opts.coordPrecision ?? 5;
  const round = (v) => Number(v.toFixed(precision));
  const features = [];
  for (const s of shapes) {
    if (!(s.tripsPerDay > 0) || !Array.isArray(s.polyline) || s.polyline.length < 2) continue;
    features.push({
      type: "Feature",
      properties: { type: s.vehicleType, trips: s.tripsPerDay },
      geometry: {
        type: "MultiPoint",
        coordinates: resample(s.polyline, step).map(([lat, lon]) => [round(lon), round(lat)]),
      },
    });
  }
  return { type: "FeatureCollection", features };
}
