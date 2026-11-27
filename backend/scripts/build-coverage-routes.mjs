#!/usr/bin/env node
// Builds public/gtfs/coverage-routes.json: coverage mode's route traces. Every
// city route direction with its vehicle type, weekday trips (from
// public/gtfs/trips/<route_id>.json) and a compact simplified polyline; the
// app draws them as additive threads. Served via GET /api/v1/coverage/routes.
// Geometry logic: coverage-core.mjs.
//
// Run after build-trips.mjs (the npm `gtfs:build` script chains it).
import { existsSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";
import { buildCoverageRoutes } from "./coverage-core.mjs";

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
    shapes.push({ vehicleType: l.vehicle_type, tripsPerDay: tripsPerDay(l.route_id), polyline: shape.polyline ?? [] });
  }
  const out = buildCoverageRoutes(shapes);
  const outPath = join(OUT_DIR, "coverage-routes.json");
  const json = JSON.stringify(out);
  writeFileSync(outPath, json);
  const pts = out.routes.reduce((n, r) => n + r.p.length / 2, 0);
  console.log(
    `Wrote ${outPath}: ${out.routes.length} routes, ${pts} points, ` +
      `${(statSync(outPath).size / 1024).toFixed(0)} KB raw, ~${(gzipSync(json).length / 1024).toFixed(0)} KB gzip`,
  );
}

main();
