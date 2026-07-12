#!/usr/bin/env node
// Builds public/gtfs/coverage.geojson — the coverage map's *render* layer: the
// raw GTFS route shapes as-is (one LineString per direction), no collapsing, no
// grid. The client draws them as many semi-transparent lines so overlaps build
// up brightness (Strava-heatmap style). Served via GET /api/v1/coverage.
//
// The separate build-coverage.mjs still precomputes the collapsed, route-counted
// layer (coverage-weighted.geojson) for future data-driven weights — it's just
// not on the render path anymore.
//
// Runs after build-gtfs.mjs (npm `gtfs:build` chains them). Geometry logic lives
// in coverage-core.mjs so it's unit-testable without file I/O.
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";
import { buildCoverageLines } from "./coverage-core.mjs";

const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");

// Geometry-preserving simplify tolerance in degrees. 0 = keep raw geometry;
// raised only if the file gets too heavy (see below). ~0.00002° ≈ 2 m.
const SIMPLIFY_EPSILON = 0.00002;
const GZIP_BUDGET_KB = 2048;

function main() {
  const linesPath = join(OUT_DIR, "lines.json");
  if (!existsSync(linesPath)) {
    console.error(`Missing ${linesPath}. Run \`npm run gtfs:build\` first (it chains this).`);
    process.exit(1);
  }

  const { lines } = JSON.parse(readFileSync(linesPath, "utf-8"));
  console.log(`Reading ${lines.length} line/direction entries ...`);

  const shapes = [];
  let missing = 0;
  for (const l of lines) {
    const shapePath = join(OUT_DIR, "shapes", `${l.route_id}.json`);
    if (!existsSync(shapePath)) {
      missing++;
      continue;
    }
    const shape = JSON.parse(readFileSync(shapePath, "utf-8"));
    shapes.push({ line: l.line, vehicleType: l.vehicle_type, polyline: shape.polyline ?? [] });
  }
  if (missing) console.log(`  (${missing} entries had no shape file, skipped)`);

  // Try raw first; only simplify if we blow the gzip budget, so the default
  // output keeps the exact shapes.
  let geojson = buildCoverageLines(shapes, { simplifyEpsilon: 0 });
  let json = JSON.stringify(geojson);
  let gzipKb = gzipSync(json).length / 1024;
  let note = "raw geometry";
  if (gzipKb > GZIP_BUDGET_KB) {
    geojson = buildCoverageLines(shapes, { simplifyEpsilon: SIMPLIFY_EPSILON });
    json = JSON.stringify(geojson);
    gzipKb = gzipSync(json).length / 1024;
    note = `simplified @ ${SIMPLIFY_EPSILON}°`;
  }

  const outPath = join(OUT_DIR, "coverage.geojson");
  writeFileSync(outPath, json);
  const rawKb = statSync(outPath).size / 1024;
  console.log(
    `Wrote ${outPath}: ${geojson.features.length} line features, ` +
      `${rawKb.toFixed(0)} KB raw, ~${gzipKb.toFixed(0)} KB gzip (${note})`,
  );
  console.log("Done.");
}

main();
