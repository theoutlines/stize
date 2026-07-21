#!/usr/bin/env node
// PHASE-0 analysis ONLY (not a runtime artifact yet): compute the "sentinel
// sweep" map from the static GTFS bundle. One arrivals fetch for a mid-route
// stop returns every vehicle heading to it (GPS + garage_no + all_stations),
// so one well-placed sentinel per line×direction observes that direction's
// active fleet. We greedily reuse stops that sit mid-route on several
// directions at once to minimise the number of points swept.
//
// Reads only public/gtfs/** — no source calls, no D1. Prints a summary and
// writes the chosen sentinel set to scripts/out/sentinels.json for the report.
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";

const GTFS = join(import.meta.dirname, "..", "public", "gtfs");
const OUT = join(import.meta.dirname, "out");

const lines = JSON.parse(readFileSync(join(GTFS, "lines.json"))).lines;
const stops = JSON.parse(readFileSync(join(GTFS, "stops.json"))).stops;
const stopById = new Map(stops.map((s) => [s.stop_id, s]));
const lineByRoute = new Map(lines.map((l) => [l.route_id, l]));

// Each shape file is one route_id = one line×direction with an ordered stop
// sequence. That ordered sequence is what lets us pick a mid-route stop.
const shapeFiles = readdirSync(join(GTFS, "shapes")).filter((f) => f.endsWith(".json"));

// Universe: every line×direction we want a sentinel for. Skip purely-suburban
// lines (marked in lines.json) — this stays a *city* sweep, matching coverage.
const routeStops = new Map(); // route_id -> ordered [stop_id]
const midCandidates = new Map(); // route_id -> Set(stop_id) eligible as sentinel (middle third)
let skippedSuburban = 0;
let skippedTiny = 0;

for (const f of shapeFiles) {
  const routeId = f.replace(/\.json$/, "");
  const meta = lineByRoute.get(routeId);
  if (meta?.suburban) {
    skippedSuburban++;
    continue;
  }
  const shape = JSON.parse(readFileSync(join(GTFS, "shapes", f)));
  const seq = shape.stops.map((s) => s.stop_id);
  if (seq.length < 3) {
    skippedTiny++;
    continue;
  }
  routeStops.set(routeId, seq);
  // Eligible sentinel stops = the middle third of the ordered sequence. A
  // mid-route stop maximises the number of in-service vehicles currently
  // approaching it, and the band (not just the single midpoint) gives the
  // set-cover room to reuse one stop across several lines.
  const lo = Math.floor(seq.length * 0.34);
  const hi = Math.ceil(seq.length * 0.66);
  midCandidates.set(routeId, new Set(seq.slice(lo, hi)));
}

const universe = [...routeStops.keys()];

// Invert: candidate stop -> set of route_ids it can sentinel (is mid-route on).
const stopCovers = new Map(); // stop_id -> Set(route_id)
for (const [routeId, cands] of midCandidates) {
  for (const stopId of cands) {
    let set = stopCovers.get(stopId);
    if (!set) stopCovers.set(stopId, (set = new Set()));
    set.add(routeId);
  }
}

// Greedy minimum set cover: repeatedly take the stop that covers the most
// still-uncovered line×directions.
function greedyCover(uncovered) {
  const chosen = [];
  const remaining = new Set(uncovered);
  // Work on mutable copies of each stop's coverage set.
  const cover = new Map([...stopCovers].map(([s, set]) => [s, new Set(set)]));
  while (remaining.size > 0) {
    let best = null;
    let bestN = 0;
    for (const [stopId, set] of cover) {
      let n = 0;
      for (const r of set) if (remaining.has(r)) n++;
      if (n > bestN) {
        bestN = n;
        best = stopId;
      }
    }
    if (!best) break; // no candidate can cover the rest (shouldn't happen)
    const covered = [...cover.get(best)].filter((r) => remaining.has(r));
    chosen.push({ stop_id: best, covers: covered });
    for (const r of covered) remaining.delete(r);
    cover.delete(best);
  }
  return { chosen, leftover: [...remaining] };
}

const pass1 = greedyCover(universe);

// Second sentinel per line×direction (redundancy): run the cover again over the
// same universe but forbidding each direction's first-pass stop, so every
// line×direction gets a distinct backup mid-route observer. This is the
// "1–2 stops per line×direction" upper bound.
const firstStopOf = new Map(); // route_id -> stop_id chosen in pass1
for (const c of pass1.chosen) for (const r of c.covers) if (!firstStopOf.has(r)) firstStopOf.set(r, c.stop_id);

const stopCovers2 = new Map();
for (const [routeId, cands] of midCandidates) {
  for (const stopId of cands) {
    if (firstStopOf.get(routeId) === stopId) continue; // exclude the pass-1 pick for this dir
    let set = stopCovers2.get(stopId);
    if (!set) stopCovers2.set(stopId, (set = new Set()));
    set.add(routeId);
  }
}
function greedyCover2(uncovered, coversMap) {
  const chosen = [];
  const remaining = new Set(uncovered);
  const cover = new Map([...coversMap].map(([s, set]) => [s, new Set(set)]));
  while (remaining.size > 0) {
    let best = null;
    let bestN = 0;
    for (const [stopId, set] of cover) {
      let n = 0;
      for (const r of set) if (remaining.has(r)) n++;
      if (n > bestN) {
        bestN = n;
        best = stopId;
      }
    }
    if (!best) break;
    const covered = [...cover.get(best)].filter((r) => remaining.has(r));
    chosen.push({ stop_id: best, covers: covered });
    for (const r of covered) remaining.delete(r);
    cover.delete(best);
  }
  return { chosen, leftover: [...remaining] };
}
const pass2 = greedyCover2(universe, stopCovers2);

// The union of pass1 + pass2 stops = the redundant (2-sentinel) sweep set.
const setBoth = new Set([...pass1.chosen.map((c) => c.stop_id), ...pass2.chosen.map((c) => c.stop_id)]);

const distinctLines = new Set(lines.filter((l) => !l.suburban).map((l) => l.line)).size;

console.log("=== Sentinel sweep — Phase 0 map ===");
console.log(`city line×directions (universe):   ${universe.length}`);
console.log(`distinct city line numbers:        ${distinctLines}`);
console.log(`skipped suburban route-dirs:       ${skippedSuburban}`);
console.log(`skipped <3-stop route-dirs:        ${skippedTiny}`);
console.log("");
console.log(`PASS 1 (1 sentinel / line-dir, greedy reuse):`);
console.log(`  sentinel stops:                  ${pass1.chosen.length}`);
console.log(`  line-dirs left uncovered:        ${pass1.leftover.length}`);
console.log(`  reuse factor:                    ${(universe.length / pass1.chosen.length).toFixed(2)} line-dirs / stop`);
console.log("");
console.log(`PASS 1+2 (redundant, 2 sentinels / line-dir):`);
console.log(`  total distinct sentinel stops:   ${setBoth.size}`);
console.log("");
const top = [...pass1.chosen].sort((a, b) => b.covers.length - a.covers.length).slice(0, 10);
console.log("Top sentinels by line-dirs covered (pass 1):");
for (const c of top) {
  const s = stopById.get(c.stop_id);
  console.log(`  ${c.stop_id}  ${(s?.name ?? "?").padEnd(26)} covers ${c.covers.length} line-dirs`);
}

// Analysis dump (human-readable, kept out of the deployed bundle).
mkdirSync(OUT, { recursive: true });
writeFileSync(
  join(OUT, "sentinels.json"),
  JSON.stringify(
    {
      universe: universe.length,
      distinct_lines: distinctLines,
      pass1_count: pass1.chosen.length,
      redundant_count: setBoth.size,
      pass1: pass1.chosen.map((c) => ({
        stop_id: c.stop_id,
        name: stopById.get(c.stop_id)?.name ?? null,
        covers: c.covers.length,
      })),
    },
    null,
    2,
  ),
);
console.log(`\nWrote ${join(OUT, "sentinels.json")} (analysis)`);

// Runtime artifact served to the Worker: just the minimal-set stop ids, in
// sweep order (most-covering first, so an interrupted cycle still hit the
// highest-value observers). Regenerated by `npm run gtfs:build`.
const feedMeta = JSON.parse(readFileSync(join(GTFS, "feed_meta.json")));
const ordered = [...pass1.chosen].sort((a, b) => b.covers.length - a.covers.length);
writeFileSync(
  join(GTFS, "sentinels.json"),
  JSON.stringify({
    built_from_feed: feedMeta.feed_version ?? null,
    count: ordered.length,
    covers_line_dirs: universe.length,
    stops: ordered.map((c) => c.stop_id),
  }),
);
console.log(`Wrote ${join(GTFS, "sentinels.json")} (runtime, ${ordered.length} stops)`);
