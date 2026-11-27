#!/usr/bin/env node
// Builds public/gtfs/coverage-flow.geojson: coverage mode's flow lines. Per
// vehicle type, city routes collapse into shared corridors carrying `trips`
// (weekday trips of every route direction along them, from
// public/gtfs/trips/<route_id>.json); the client maps `trips` to line width.
// Served via GET /api/v1/coverage/flow. Geometry logic: coverage-core.mjs.
//
// Run after build-trips.mjs (the npm `gtfs:build` script chains it).
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";
import { buildCoverageFlow } from "./coverage-core.mjs";

const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");

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
  for (const l of lines) {
    // City coverage only, like the other coverage builds.
    if (l.suburban) continue;
    const shapePath = join(OUT_DIR, "shapes", `${l.route_id}.json`);
    if (!existsSync(shapePath)) continue;
    const shape = JSON.parse(readFileSync(shapePath, "utf-8"));
    shapes.push({
      routeId: l.route_id,
      vehicleType: l.vehicle_type,
      tripsPerDay: tripsPerDay(l.route_id),
      polyline: shape.polyline ?? [],
    });
  }
  const geojson = buildCoverageFlow(shapes);
  const outPath = join(OUT_DIR, "coverage-flow.geojson");
  const json = JSON.stringify(geojson);
  writeFileSync(outPath, json);
  const trips = geojson.features.map((f) => f.properties.trips);
  console.log(
    `Wrote ${outPath}: ${geojson.features.length} corridors, trips ${Math.min(...trips)}..${Math.max(...trips)}, ` +
      `${(statSync(outPath).size / 1024).toFixed(0)} KB raw, ~${(gzipSync(json).length / 1024).toFixed(0)} KB gzip`,
  );
}

main();
