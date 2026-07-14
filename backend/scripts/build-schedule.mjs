#!/usr/bin/env node
// Precomputes a compact per-stop scheduled-departures index for the schedule
// fallback (Phase 1 — the stop arrivals list). The Worker can't parse the 110 MB
// stop_times at request time, so this bakes, per *city* stop, the planned
// departure times of every line/direction that serves it, grouped by GTFS
// service (RD weekday / S Saturday / N Sunday). At request time the Worker picks
// the active service(s) for the date and the times after "now".
//
// Output: public/gtfs/schedule/<stop_id>.json (fetched per stop, like shapes) +
// schedule/_meta.json (feeds' service window / build time). Times are seconds
// since midnight; overnight trips keep GTFS values >86400 (e.g. 25:30 -> 91800).
import { createReadStream, existsSync, mkdirSync, readFileSync, writeFileSync, rmSync, statSync } from "node:fs";
import { createInterface } from "node:readline";
import { gzipSync } from "node:zlib";
import { join } from "node:path";

const RAW_DIR = join(import.meta.dirname, "..", "gtfs_raw", "extracted");
const SUB_RAW_DIR = join(import.meta.dirname, "..", "gtfs_raw", "suburban");
const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");
const SCHED_DIR = join(OUT_DIR, "schedule");

function splitCsvLine(line) {
  return line.split(",");
}
async function readCsv(path, onRow) {
  const rl = createInterface({ input: createReadStream(path, "utf-8"), crlfDelay: Infinity });
  let header = null;
  for await (const line of rl) {
    if (line === "") continue;
    if (header === null) {
      header = splitCsvLine(line);
      continue;
    }
    const cols = splitCsvLine(line);
    const row = {};
    for (let i = 0; i < header.length; i++) row[header[i]] = cols[i] ?? "";
    onRow(row);
  }
}

// "HH:MM:SS" -> minutes since midnight (schedules are minute-precision, so
// seconds are dropped — ~20% smaller index). Overnight trips keep GTFS values
// >1440 (e.g. 25:30 -> 1530), which the Worker maps into the small hours.
function toMinutes(hms) {
  const m = /^(\d+):(\d+):(\d+)$/.exec(hms);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

async function main() {
  if (!existsSync(RAW_DIR)) {
    console.error(`Raw GTFS not found at ${RAW_DIR}. Run the feed download first.`);
    process.exit(1);
  }
  // City stops define scope — schedule is built only for stops we actually show.
  const bundleStops = JSON.parse(readFileSync(join(OUT_DIR, "stops.json"), "utf-8")).stops;
  const cityStopIds = new Set(bundleStops.map((s) => s.stop_id));

  // (rawRouteId, direction_id) -> bundle route_id / line, from lines.json.
  const { lines: bundleLines } = JSON.parse(readFileSync(join(OUT_DIR, "lines.json"), "utf-8"));
  const routeDirToBundle = new Map(); // `${rawRouteId}::${dir}` -> { routeId, line }
  for (const l of bundleLines) {
    const raw = l.route_id.replace(/-\d+$/, "");
    routeDirToBundle.set(`${raw}::${l.direction_id ?? "0"}`, { routeId: l.route_id, line: l.line });
  }

  // stop_id -> route_id -> { line, dir, svc: { RD:Set, S:Set, N:Set } }
  const byStop = new Map();

  async function readFeed(dir, { skipRouteIds } = {}) {
    if (!existsSync(join(dir, "trips.txt"))) return;
    const tripRoute = new Map();
    const tripDir = new Map();
    const tripService = new Map();
    await readCsv(join(dir, "trips.txt"), (t) => {
      if (skipRouteIds && skipRouteIds.has(t.route_id)) return;
      tripRoute.set(t.trip_id, t.route_id);
      tripDir.set(t.trip_id, t.direction_id || "0");
      tripService.set(t.trip_id, t.service_id);
    });
    await readCsv(join(dir, "stop_times.txt"), (row) => {
      if (!cityStopIds.has(row.stop_id)) return; // targeted: city stops only
      const rawRouteId = tripRoute.get(row.trip_id);
      if (!rawRouteId) return;
      const dir = tripDir.get(row.trip_id);
      const svc = tripService.get(row.trip_id);
      const bundle = routeDirToBundle.get(`${rawRouteId}::${dir}`);
      if (!bundle) return; // route/direction not in the served bundle
      const mins = toMinutes(row.departure_time);
      if (mins === null) return;
      let stop = byStop.get(row.stop_id);
      if (!stop) byStop.set(row.stop_id, (stop = new Map()));
      let entry = stop.get(bundle.routeId);
      if (!entry) {
        entry = { line: bundle.line, dir, svc: { RD: new Set(), S: new Set(), N: new Set() } };
        stop.set(bundle.routeId, entry);
      }
      if (entry.svc[svc]) entry.svc[svc].add(mins);
    });
  }

  // The shared 600-series live in both feeds identically — read them from the
  // suburban feed only (matching the bundle) so their departures aren't doubled.
  const collisionRouteIds = new Set();
  if (existsSync(join(SUB_RAW_DIR, "routes.txt"))) {
    const cityRouteIds = new Set();
    await readCsv(join(RAW_DIR, "routes.txt"), (r) => cityRouteIds.add(r.route_id));
    await readCsv(join(SUB_RAW_DIR, "routes.txt"), (r) => {
      if (cityRouteIds.has(r.route_id)) collisionRouteIds.add(r.route_id);
    });
  }

  console.log("Reading city schedule ...");
  await readFeed(RAW_DIR, { skipRouteIds: collisionRouteIds });
  console.log("Reading suburban schedule ...");
  await readFeed(SUB_RAW_DIR);

  // --- Write per-stop files ---
  rmSync(SCHED_DIR, { recursive: true, force: true });
  mkdirSync(SCHED_DIR, { recursive: true });
  let files = 0;
  let totalDepartures = 0;
  for (const [stopId, routes] of byStop) {
    const deps = [];
    for (const [routeId, e] of routes) {
      const svc = {};
      for (const key of ["RD", "S", "N"]) {
        if (e.svc[key].size) {
          svc[key] = [...e.svc[key]].sort((a, b) => a - b);
          totalDepartures += svc[key].length;
        }
      }
      deps.push({ line: e.line, route_id: routeId, dir: e.dir, svc });
    }
    deps.sort((a, b) => lineCompare(a.line, b.line));
    writeFileSync(join(SCHED_DIR, `${stopId}.json`), JSON.stringify({ stop_id: stopId, deps }));
    files++;
  }

  // Calendar + exceptions, so the Worker can resolve the active service(s) for a
  // date. Both feeds share the RD/S/N services; exceptions (holidays) are merged.
  const services = {}; // service_id -> {mon..sun: 0|1}
  const DOW = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
  const exceptions = {}; // "YYYY-MM-DD" -> { add: [], remove: [] }
  for (const feed of [RAW_DIR, SUB_RAW_DIR]) {
    if (!existsSync(join(feed, "calendar.txt"))) continue;
    await readCsv(join(feed, "calendar.txt"), (r) => {
      services[r.service_id] = {
        monday: +r.monday, tuesday: +r.tuesday, wednesday: +r.wednesday,
        thursday: +r.thursday, friday: +r.friday, saturday: +r.saturday, sunday: +r.sunday,
      };
    });
    if (existsSync(join(feed, "calendar_dates.txt"))) {
      await readCsv(join(feed, "calendar_dates.txt"), (r) => {
        const iso = `${r.date.slice(0, 4)}-${r.date.slice(4, 6)}-${r.date.slice(6, 8)}`;
        const e = (exceptions[iso] ??= { add: [], remove: [] });
        const bucket = r.exception_type === "1" ? e.add : e.remove;
        if (!bucket.includes(r.service_id)) bucket.push(r.service_id);
      });
    }
  }

  writeFileSync(
    join(SCHED_DIR, "_meta.json"),
    JSON.stringify({
      built_at: new Date().toISOString(),
      stops: files,
      departures: totalDepartures,
      unit: "minutes",
      services,
      exceptions,
      dow: DOW,
    }),
  );

  // Size report (the coverage lesson: measure before shipping).
  let rawBytes = 0;
  let gzipBytes = 0;
  for (const [stopId, routes] of byStop) {
    const buf = readFileSync(join(SCHED_DIR, `${stopId}.json`));
    rawBytes += buf.length;
    gzipBytes += gzipSync(buf).length;
    void routes;
  }
  console.log(
    `Wrote ${files} per-stop schedule files, ${totalDepartures} departures. ` +
      `Raw ${(rawBytes / 1024 / 1024).toFixed(1)} MB, ~${(gzipBytes / 1024 / 1024).toFixed(1)} MB gzip total ` +
      `(avg ${(rawBytes / files).toFixed(0)} B raw / stop).`,
  );
  console.log("Done.");
}

function lineCompare(a, b) {
  const na = parseInt(a, 10);
  const nb = parseInt(b, 10);
  if (!Number.isNaN(na) && !Number.isNaN(nb) && na !== nb) return na - nb;
  return a.localeCompare(b);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
