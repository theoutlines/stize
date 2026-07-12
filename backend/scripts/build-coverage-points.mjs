#!/usr/bin/env node
// Builds public/gtfs/coverage.geojson — the coverage map's *render* layer for a
// MapLibre heatmap: every GTFS route shape resampled to evenly-spaced points.
// Each route contributes its own points, so overlapping routes raise the local
// point density, which the heatmap turns into brightness (Strava-heatmap style).
// Served via GET /api/v1/coverage.
//
// The separate build-coverage.mjs still precomputes the collapsed, route-counted
// layer (coverage-weighted.geojson) for future data-driven weights — off the
// render path. Geometry logic lives in coverage-core.mjs (unit-testable, no I/O).
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";
import { buildCoveragePoints } from "./coverage-core.mjs";

const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");

// Sample spacing in metres. ~90 m is finely sampled relative to the heatmap
// radius (which is much larger), keeps the file light (~0.5 MB gzip), and reads
// smoothly at every zoom. Bump it if the point file gets too heavy.
const STEP_METRES = 90;
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

  console.log(`Resampling shapes to points every ~${STEP_METRES} m ...`);
  const geojson = buildCoveragePoints(shapes, { stepMetres: STEP_METRES });

  const outPath = join(OUT_DIR, "coverage.geojson");
  const json = JSON.stringify(geojson);
  writeFileSync(outPath, json);
  const rawKb = statSync(outPath).size / 1024;
  const gzipKb = gzipSync(json).length / 1024;
  console.log(
    `Wrote ${outPath}: ${geojson.features.length} points, ` +
      `${rawKb.toFixed(0)} KB raw, ~${gzipKb.toFixed(0)} KB gzip`,
  );
  if (gzipKb > GZIP_BUDGET_KB) {
    console.warn(`  ⚠ over ~${GZIP_BUDGET_KB} KB gzip — raise STEP_METRES or split into coarse/detailed sources.`);
  }
  console.log("Done.");
}

main();
