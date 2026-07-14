#!/usr/bin/env node
// Precomputes a per-route timed-trip index for schedule fallback Phase 2 (the
// map). For each served route it lists every trip's departure minute at each of
// the route's shape stops (aligned to shapes/<route_id>.json's stop order, null
// where a trip skips a stop). At request time the Worker finds trips in transit
// now and interpolates their position along the shape — but only for lines that
// have no live vehicle, so a busy live viewport stays cheap.
//
// Output: public/gtfs/trips/<route_id>.json (fetched per route, like shapes).
// Times are minutes since midnight; overnight keeps values >=1440.
import { createReadStream, existsSync, mkdirSync, readFileSync, writeFileSync, rmSync, statSync } from "node:fs";
import { createInterface } from "node:readline";
import { gzipSync } from "node:zlib";
import { join } from "node:path";

const RAW_DIR = join(import.meta.dirname, "..", "gtfs_raw", "extracted");
const SUB_RAW_DIR = join(import.meta.dirname, "..", "gtfs_raw", "suburban");
const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");
const TRIPS_DIR = join(OUT_DIR, "trips");

async function readCsv(path, onRow) {
  const rl = createInterface({ input: createReadStream(path, "utf-8"), crlfDelay: Infinity });
  let header = null;
  for await (const line of rl) {
    if (line === "") continue;
    if (header === null) { header = line.split(","); continue; }
    const cols = line.split(",");
    const row = {};
    for (let i = 0; i < header.length; i++) row[header[i]] = cols[i] ?? "";
    onRow(row);
  }
}
const toMinutes = (t) => {
  const m = /^(\d+):(\d+):/.exec(t);
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};

async function main() {
  // (rawRouteId, dir) -> bundle route_id, from lines.json.
  const bundleLines = JSON.parse(readFileSync(join(OUT_DIR, "lines.json"), "utf-8")).lines;
  const rdToBundle = new Map();
  for (const l of bundleLines) {
    const raw = l.route_id.replace(/-\d+$/, "");
    rdToBundle.set(`${raw}::${l.direction_id ?? "0"}`, l.route_id);
  }
  // bundle route_id -> ordered shape stop_ids (position reference for alignment).
  const shapeStops = new Map();
  for (const l of bundleLines) {
    if (shapeStops.has(l.route_id)) continue;
    try {
      const shape = JSON.parse(readFileSync(join(OUT_DIR, "shapes", `${l.route_id}.json`), "utf-8"));
      shapeStops.set(l.route_id, shape.stops.map((s) => s.stop_id));
    } catch {
      shapeStops.set(l.route_id, []);
    }
  }

  // bundle route_id -> [ { trip_id, service, byStop: Map(stop_id->minute) } ]
  const byRoute = new Map();
  async function readFeed(dir, skipRouteIds) {
    if (!existsSync(join(dir, "trips.txt"))) return;
    const tripRoute = new Map(), tripDir = new Map(), tripSvc = new Map();
    await readCsv(join(dir, "trips.txt"), (t) => {
      if (skipRouteIds && skipRouteIds.has(t.route_id)) return;
      tripRoute.set(t.trip_id, t.route_id);
      tripDir.set(t.trip_id, t.direction_id || "0");
      tripSvc.set(t.trip_id, t.service_id);
    });
    const trips = new Map(); // trip_id -> { bundle, service, byStop }
    await readCsv(join(dir, "stop_times.txt"), (row) => {
      const rawRouteId = tripRoute.get(row.trip_id);
      if (!rawRouteId) return;
      const bundle = rdToBundle.get(`${rawRouteId}::${tripDir.get(row.trip_id)}`);
      if (!bundle) return;
      const m = toMinutes(row.departure_time);
      if (m === null) return;
      let t = trips.get(row.trip_id);
      if (!t) trips.set(row.trip_id, (t = { bundle, service: tripSvc.get(row.trip_id), byStop: new Map() }));
      t.byStop.set(row.stop_id, m);
    });
    for (const [tripId, t] of trips) {
      let arr = byRoute.get(t.bundle);
      if (!arr) byRoute.set(t.bundle, (arr = []));
      arr.push({ trip_id: tripId, service: t.service, byStop: t.byStop });
    }
  }

  // 600-series live in both feeds identically — read from suburban only.
  const cityRouteIds = new Set();
  await readCsv(join(RAW_DIR, "routes.txt"), (r) => cityRouteIds.add(r.route_id));
  const collisionRouteIds = new Set();
  if (existsSync(join(SUB_RAW_DIR, "routes.txt"))) {
    await readCsv(join(SUB_RAW_DIR, "routes.txt"), (r) => {
      if (cityRouteIds.has(r.route_id)) collisionRouteIds.add(r.route_id);
    });
  }
  console.log("Reading city trips ...");
  await readFeed(RAW_DIR, collisionRouteIds);
  console.log("Reading suburban trips ...");
  await readFeed(SUB_RAW_DIR, null);

  rmSync(TRIPS_DIR, { recursive: true, force: true });
  mkdirSync(TRIPS_DIR, { recursive: true });
  let files = 0, totalTrips = 0, raw = 0, gzip = 0;
  const cityStops = new Set(JSON.parse(readFileSync(join(OUT_DIR, "stops.json"), "utf-8")).stops.map((s) => s.stop_id));
  for (const [routeId, trips] of byRoute) {
    const stops = shapeStops.get(routeId) ?? [];
    if (stops.length === 0) continue;
    // A route is only mappable in-city if its shape touches a city stop.
    if (!stops.some((s) => cityStops.has(s))) continue;
    const out = [];
    for (const t of trips) {
      // Align the trip's times to the shape stop order (null where skipped).
      const times = stops.map((s) => (t.byStop.has(s) ? t.byStop.get(s) : null));
      if (times.every((x) => x === null)) continue;
      out.push({ trip_id: t.trip_id, service: t.service, times });
    }
    if (out.length === 0) continue;
    const buf = Buffer.from(JSON.stringify({ route_id: routeId, trips: out }));
    writeFileSync(join(TRIPS_DIR, `${routeId}.json`), buf);
    raw += buf.length;
    gzip += gzipSync(buf).length;
    totalTrips += out.length;
    files++;
  }
  console.log(
    `Wrote ${files} per-route trip files, ${totalTrips} trips. ` +
      `Raw ${(raw / 1048576).toFixed(1)} MB, ~${(gzip / 1048576).toFixed(1)} MB gzip total ` +
      `(avg ${(raw / files / 1024).toFixed(1)} KB raw / route).`,
  );
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
