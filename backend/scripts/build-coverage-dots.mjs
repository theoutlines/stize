#!/usr/bin/env node
// Builds public/gtfs/coverage-dots.geojson: the coverage mode's dot cloud. Every
// city route's shape is scattered with dots in proportion to its weekday trips
// (public/gtfs/trips/<route_id>.json), so the map shows how often transit runs
// where, not just how many lines pass. One MultiPoint per vehicle type.
// Served via GET /api/v1/coverage/dots. Geometry logic: coverage-core.mjs.
//
// Run after build-trips.mjs (the npm `gtfs:build` script chains it).
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";
import { buildCoverageDots } from "./coverage-core.mjs";

const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");
const GZIP_BUDGET_KB = 2048;

/** Weekday ("RD") trips of one route direction; the busiest other day if it
 * runs no weekday service. 0 when the route has no trip file. */
function tripsPerDay(routeId) {
  const path = join(OUT_DIR, "trips", `${routeId}.json`);
  if (!existsSync(path)) return 0;
  const counts = {};
  for (const t of JSON.parse(readFileSync(path, "utf-8")).trips ?? []) {
    counts[t.service] = (counts[t.service] ?? 0) + 1;
  }
  return counts.RD ?? Math.max(0, ...Object.values(counts));
}

function main() {
  const linesPath = join(OUT_DIR, "lines.json");
  if (!existsSync(linesPath)) {
    console.error(`Missing ${linesPath}. Run \`npm run gtfs:build\` first (it chains this).`);
    process.exit(1);
  }
  const { lines } = JSON.parse(readFileSync(linesPath, "utf-8"));
  const shapes = [];
  let noTrips = 0;
  for (const l of lines) {
    // City coverage only, like the heatmap points (see build-coverage-points).
    if (l.suburban) continue;
    const shapePath = join(OUT_DIR, "shapes", `${l.route_id}.json`);
    if (!existsSync(shapePath)) continue;
    const trips = tripsPerDay(l.route_id);
    if (trips === 0) noTrips++;
    const shape = JSON.parse(readFileSync(shapePath, "utf-8"));
    shapes.push({ vehicleType: l.vehicle_type, tripsPerDay: trips, polyline: shape.polyline ?? [] });
  }
  if (noTrips) console.log(`  (${noTrips} route directions without trips, skipped)`);

  const geojson = buildCoverageDots(shapes, { coordPrecision: 5 });
  const outPath = join(OUT_DIR, "coverage-dots.geojson");
  const json = JSON.stringify(geojson);
  writeFileSync(outPath, json);
  const dots = geojson.features.reduce((n, f) => n + f.geometry.coordinates.length, 0);
  const rawKb = statSync(outPath).size / 1024;
  const gzipKb = gzipSync(json).length / 1024;
  console.log(`Wrote ${outPath}: ${dots} dots, ${rawKb.toFixed(0)} KB raw, ~${gzipKb.toFixed(0)} KB gzip`);
  if (gzipKb > GZIP_BUDGET_KB) console.warn(`  ⚠ over ~${GZIP_BUDGET_KB} KB gzip — lower the dot budget.`);
}

main();
