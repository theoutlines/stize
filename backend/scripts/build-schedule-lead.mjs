#!/usr/bin/env node
// Adds a "lead" to every planned departure in public/gtfs/schedule/<stop>.json:
// how many minutes the trip has already been travelling when it reaches this
// stop (time at this stop minus the trip's first departure). The arrivals
// endpoint uses it for the reachability rule: a planned departure is shown only
// if its trip has not left the terminus yet (eta >= lead - grace). A trip that
// is already on the road without a live vehicle is a phantom: it is not shown.
//
// Derived from the already-built trips/<route_id>.json (times aligned to the
// route's shape stops) and shapes/<route_id>.json (the stop ids), so it runs
// after build-trips.mjs and needs no raw GTFS. `lead` is aligned 1:1 with the
// `svc` minute arrays; when several trips share the same minute at a stop the
// smallest lead wins (the most reachable one). null = no trip data for that
// departure (the client and Worker keep those: they cannot be judged).
import { readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const OUT_DIR = join(import.meta.dirname, "..", "public", "gtfs");
const SCHED_DIR = join(OUT_DIR, "schedule");
const TRIPS_DIR = join(OUT_DIR, "trips");
const SHAPES_DIR = join(OUT_DIR, "shapes");

// `${stopId}|${routeId}|${service}|${minute}` -> smallest lead (minutes)
const leads = new Map();

for (const file of readdirSync(TRIPS_DIR)) {
  if (!file.endsWith(".json")) continue;
  const routeId = file.slice(0, -5);
  const shapePath = join(SHAPES_DIR, file);
  if (!existsSync(shapePath)) continue;
  const { trips } = JSON.parse(readFileSync(join(TRIPS_DIR, file), "utf-8"));
  const { stops } = JSON.parse(readFileSync(shapePath, "utf-8"));
  for (const trip of trips) {
    let first = null;
    for (const t of trip.times) {
      if (t !== null) {
        first = t;
        break;
      }
    }
    if (first === null) continue;
    for (let i = 0; i < trip.times.length; i++) {
      const t = trip.times[i];
      const stop = stops[i];
      if (t === null || !stop) continue;
      const key = `${stop.stop_id}|${routeId}|${trip.service}|${t}`;
      const lead = t - first;
      const prev = leads.get(key);
      if (prev === undefined || lead < prev) leads.set(key, lead);
    }
  }
}

let total = 0;
let known = 0;
for (const file of readdirSync(SCHED_DIR)) {
  if (!file.endsWith(".json") || file.startsWith("_")) continue;
  const path = join(SCHED_DIR, file);
  const sched = JSON.parse(readFileSync(path, "utf-8"));
  for (const dep of sched.deps) {
    const lead = {};
    for (const [svc, mins] of Object.entries(dep.svc)) {
      lead[svc] = mins.map((m) => {
        total++;
        const v = leads.get(`${sched.stop_id}|${dep.route_id}|${svc}|${m}`);
        if (v === undefined) return null;
        known++;
        return v;
      });
    }
    dep.lead = lead;
  }
  writeFileSync(path, JSON.stringify(sched));
}

const pct = total ? ((known / total) * 100).toFixed(1) : "0";
console.log(`schedule lead: ${known}/${total} departures matched to a trip (${pct}%)`);
