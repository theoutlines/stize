// Pure, I/O-free core of the GTFS bundle build (see build-gtfs.mjs for the
// file-reading runner). Kept separate — like coverage-core.mjs — so the parts
// that carry real product decisions can be unit-tested in the Workers vitest
// pool without touching node:fs.
//
// Three concerns live here:
//   1. deriveStopTypes  — a stop's vehicle types come from the feed's
//      authoritative route_type (line → type), never from guessing by line
//      number. This is the data half of the "type by feed, not by number" fix
//      (the client half is app/lib/core/map_support.dart).
//   2. applyStopOverrides — a provenance-carrying, point patch to stop
//      coordinates, applied at BUILD time so stops.json / nearby / RAPTOR all
//      get the corrected geometry. Absent/empty file ⇒ no-op (build unchanged).
//   3. tramStopsWithoutRail — the build-time guard: how many stops end up typed
//      tram yet have no tram rail within 40 m. Expected 0 after the fix; a
//      growth is a loud signal that the type source regressed.

// Marker/type priority order, tram → trolleybus → bus. A stop served by any
// tram line reads as a tram stop (owner rule); this ordering makes the emitted
// `types` array deterministic and lets the client apply the same priority.
export const TYPE_ORDER = ["tram", "trolleybus", "bus"];

/// The distinct vehicle types serving a stop, from the feed's per-line type.
/// `lineTypeByNumber`: Map<lineNumber, "tram"|"trolleybus"|"bus"> built from
/// route_type. A line with no known type falls back to "bus" (same default the
/// backend arrivals path uses), so an unmapped live-only line never invents a
/// tram. Returns types in TYPE_ORDER.
export function deriveStopTypes(lines, lineTypeByNumber) {
  const present = new Set();
  for (const line of lines) present.add(lineTypeByNumber.get(line) ?? "bus");
  return TYPE_ORDER.filter((t) => present.has(t));
}

/// Applies a stop-overrides document to a `Map<stop_id, {lat, lon, ...}>` in
/// place. Supported ops:
///   - { op: "swap_coords", stop_ids: [a, b] }  — swap the two stops' lat/lon
///     (a feed defect that puts a direction pair on each other's side).
///   - { op: "set_coords", stop_id, lat, lon }  — set one stop's coordinate.
/// Every entry must also carry `reason`, `date`, `evidence` (provenance) — a
/// coordinate patch without a paper trail is refused, so overrides can't
/// silently accrete. A referenced stop_id that isn't in the feed throws (a
/// stale override must be noticed, not quietly skipped). `doc` null/empty ⇒ the
/// no-op path, so a missing file leaves the build exactly as it was.
/// Returns { applied, details }.
export function applyStopOverrides(stopsById, doc) {
  const details = [];
  if (!doc || !Array.isArray(doc.overrides) || doc.overrides.length === 0) {
    return { applied: 0, details };
  }
  for (const ov of doc.overrides) {
    for (const field of ["reason", "date", "evidence"]) {
      if (!ov[field] || typeof ov[field] !== "string") {
        throw new Error(`stop override missing provenance field "${field}": ${JSON.stringify(ov)}`);
      }
    }
    const need = (id) => {
      const s = stopsById.get(id);
      if (!s) throw new Error(`stop override references unknown stop_id "${id}" (stale override?): ${JSON.stringify(ov)}`);
      return s;
    };
    if (ov.op === "swap_coords") {
      if (!Array.isArray(ov.stop_ids) || ov.stop_ids.length !== 2) {
        throw new Error(`swap_coords needs exactly two stop_ids: ${JSON.stringify(ov)}`);
      }
      const [a, b] = ov.stop_ids.map(need);
      const tmp = { lat: a.lat, lon: a.lon };
      a.lat = b.lat;
      a.lon = b.lon;
      b.lat = tmp.lat;
      b.lon = tmp.lon;
      details.push(`swap_coords ${ov.stop_ids[0]}<->${ov.stop_ids[1]}`);
    } else if (ov.op === "set_coords") {
      const s = need(ov.stop_id);
      if (typeof ov.lat !== "number" || typeof ov.lon !== "number") {
        throw new Error(`set_coords needs numeric lat/lon: ${JSON.stringify(ov)}`);
      }
      s.lat = ov.lat;
      s.lon = ov.lon;
      details.push(`set_coords ${ov.stop_id}`);
    } else {
      throw new Error(`unknown stop override op "${ov.op}": ${JSON.stringify(ov)}`);
    }
  }
  return { applied: details.length, details };
}

// --- Build-time tram-without-rail guard ------------------------------------

// Local equirectangular metres around Belgrade (~44.8°N) — good to well under a
// metre over the tens-of-metres distances this guard cares about.
const M_PER_DEG_LAT = 111320;
const M_PER_DEG_LON = 111320 * Math.cos((44.8 * Math.PI) / 180);

function distPointToSegmentM(lat, lon, aLat, aLon, bLat, bLon) {
  const px = lon * M_PER_DEG_LON, py = lat * M_PER_DEG_LAT;
  const ax = aLon * M_PER_DEG_LON, ay = aLat * M_PER_DEG_LAT;
  const bx = bLon * M_PER_DEG_LON, by = bLat * M_PER_DEG_LAT;
  const dx = bx - ax, dy = by - ay;
  const len2 = dx * dx + dy * dy;
  let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const cx = ax + t * dx, cy = ay + t * dy;
  return Math.hypot(px - cx, py - cy);
}

/// Nearest distance in metres from a point to any vertex-segment of any of the
/// given polylines ([[lat, lon], ...]). Infinity when there are no polylines.
export function nearestMetersToPolylines(lat, lon, polylines) {
  let best = Infinity;
  for (const pl of polylines) {
    // Cheap bbox reject: skip a polyline whose lat/lon span is far away.
    for (let i = 0; i + 1 < pl.length; i++) {
      const d = distPointToSegmentM(lat, lon, pl[i][0], pl[i][1], pl[i + 1][0], pl[i + 1][1]);
      if (d < best) best = d;
      if (best === 0) return 0;
    }
  }
  return best;
}

// --- Regression guard: refuse a bundle that shrinks too much ----------------

/// Compares the about-to-be-written bundle against the existing one and decides
/// whether the build may proceed. The committed bundle carries a MERGED suburban
/// feed (~340 extra lines and their city stops); a naive rebuild that forgets the
/// suburban feed silently drops all of it. This turns that silent loss into a
/// hard stop.
///
/// `baseline`/`next`: `{ stops, lines }` counts. `baseline` null (no prior
/// bundle) ⇒ nothing to lose, always ok. Any count that shrinks by MORE than
/// `maxShrinkPct` (default 2%) is a problem; `allowShrink` lets the build proceed
/// anyway (the caller must have opted in explicitly and say what's lost).
/// Returns `{ ok, blocked, allowShrink, maxShrinkPct, problems }`.
export function checkBundleShrink(baseline, next, { maxShrinkPct = 2, allowShrink = false } = {}) {
  const problems = [];
  if (baseline) {
    for (const key of ["stops", "lines"]) {
      const was = baseline[key];
      const now = next[key];
      if (typeof was === "number" && was > 0 && typeof now === "number") {
        const dropPct = ((was - now) / was) * 100;
        if (dropPct > maxShrinkPct) {
          problems.push({ key, was, now, dropPct: Math.round(dropPct * 10) / 10 });
        }
      }
    }
  }
  const blocked = problems.length > 0;
  return { ok: !blocked || allowShrink, blocked, allowShrink, maxShrinkPct, problems };
}

/// Stops that are typed `tram` but have no tram rail within `thresholdM`.
/// `stops`: [{ stop_id, name, lat, lon, types }]. `tramPolylines`: the tram
/// shapes ([[lat, lon], ...]). After the "type by feed" fix this should be 0 —
/// a tram type now implies a real tram line, which has a rail here.
export function tramStopsWithoutRail(stops, tramPolylines, thresholdM = 40) {
  const offenders = [];
  for (const s of stops) {
    if (!s.types || !s.types.includes("tram")) continue;
    const d = nearestMetersToPolylines(s.lat, s.lon, tramPolylines);
    if (d > thresholdM) offenders.push({ stop_id: s.stop_id, name: s.name, distM: Math.round(d) });
  }
  return offenders;
}
