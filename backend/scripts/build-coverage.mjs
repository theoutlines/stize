#!/usr/bin/env node
// Builds public/gtfs/coverage-weighted.geojson — the collapsed, route-counted
// coverage layer — from the built GTFS bundles (public/gtfs/lines.json +
// shapes/*.json).
//
// NOTE: this is NOT the render layer. The map renders raw shapes
// (build-coverage-lines.mjs → coverage.geojson). This weighted file is kept
// precomputed for *future* data-driven weights (frequency, observed intensity)
// per the spec, but nothing serves/draws it yet.
//
// Run after build-gtfs.mjs (the npm `gtfs:build` script chains it). The
// collapsing/counting logic lives in coverage-core.mjs (unit-testable, no I/O).
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";
import { buildCoverage } from "./coverage-core.mjs";

const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");

function main() {
  const linesPath = join(OUT_DIR, "lines.json");
  if (!existsSync(linesPath)) {
    console.error(`Missing ${linesPath}. Run \`npm run gtfs:build\` first (it chains this).`);
    process.exit(1);
  }

  const { lines } = JSON.parse(readFileSync(linesPath, "utf-8"));
  console.log(`Reading ${lines.length} line/direction entries ...`);

  // Each lines.json entry is one route direction; its shape lives in
  // shapes/<route_id>.json. Join them into the {line, vehicleType, polyline}
  // shape the core expects.
  const shapes = [];
  let missing = 0;
  for (const l of lines) {
    const shapePath = join(OUT_DIR, "shapes", `${l.route_id}.json`);
    if (!existsSync(shapePath)) {
      missing++;
      continue;
    }
    const shape = JSON.parse(readFileSync(shapePath, "utf-8"));
    shapes.push({
      line: l.line,
      vehicleType: l.vehicle_type,
      polyline: shape.polyline ?? [],
    });
  }
  if (missing) console.log(`  (${missing} entries had no shape file, skipped)`);

  console.log("Collapsing shared segments ...");
  const geojson = buildCoverage(shapes);
  const distinctLines = new Set(shapes.map((s) => s.line)).size;
  console.log(
    `  ${geojson.features.length} features from ${shapes.length} shapes (${distinctLines} distinct lines)`,
  );

  const outPath = join(OUT_DIR, "coverage-weighted.geojson");
  const json = JSON.stringify(geojson);
  writeFileSync(outPath, json);

  const rawKb = (statSync(outPath).size / 1024).toFixed(0);
  const gzipKb = (gzipSync(json).length / 1024).toFixed(0);
  console.log(`Wrote ${outPath}: ${rawKb} KB raw, ~${gzipKb} KB gzip`);
  if (gzipKb > 2048) {
    console.warn("  ⚠ over ~2 MB gzip — consider a coarser grid or stronger simplify (see coverage-core.mjs).");
  }
  console.log("Done.");
}

main();
