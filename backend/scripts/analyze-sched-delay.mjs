#!/usr/bin/env node
// One-off: run the sched_delay matching (identical logic to
// aggregateSchedDelay/schedDelaySeconds in src/lib/analytics.ts) over the
// exported staging arrivals + the local GTFS bundle. Reports match quality and
// the delay distribution, and emits UPSERT SQL to populate staging's
// sched_delay_* columns. No source calls; reads only public/gtfs/**.
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const GTFS = join(import.meta.dirname, "..", "public", "gtfs");
const arrivals = JSON.parse(readFileSync("/tmp/staging_arrivals.json"));
const meta = JSON.parse(readFileSync(join(GTFS, "schedule", "_meta.json")));

const OVERNIGHT = 1440;
const TOL = 30;

// --- verbatim from src/lib/schedule.ts ---
const TZ = "Europe/Belgrade";
function partsInTz(date) {
  const f = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });
  const p = {};
  for (const part of f.formatToParts(date)) p[part.type] = part.value;
  const hour = p.hour === "24" ? 0 : Number(p.hour);
  return { iso: `${p.year}-${p.month}-${p.day}`, minutes: hour * 60 + Number(p.minute) };
}
function belgradeNow(date) {
  const today = partsInTz(date);
  const yesterday = partsInTz(new Date(date.getTime() - 24 * 3600 * 1000));
  return { dateISO: today.iso, yesterdayISO: yesterday.iso, minutes: today.minutes };
}
function activeServices(dateISO) {
  const dow = meta.dow[new Date(`${dateISO}T00:00:00Z`).getUTCDay()];
  const active = new Set();
  for (const [svcId, days] of Object.entries(meta.services)) if (days[dow]) active.add(svcId);
  const ex = meta.exceptions[dateISO];
  if (ex) { for (const s of ex.remove) active.delete(s); for (const s of ex.add) active.add(s); }
  return active;
}
// --- verbatim from src/lib/analytics.ts ---
function schedDelaySeconds(observedMin, scheduledMins, toleranceMin = TOL) {
  let bestSigned = null, bestAbs = Infinity;
  for (const s of scheduledMins) {
    for (const cand of [s, s - OVERNIGHT, s + OVERNIGHT]) {
      const d = observedMin - cand, abs = Math.abs(d);
      if (abs < bestAbs) { bestAbs = abs; bestSigned = d; }
    }
  }
  if (bestSigned === null || bestAbs > toleranceMin) return null;
  return Math.round(bestSigned * 60);
}

const schedCache = new Map();
function loadSched(stopId) {
  if (schedCache.has(stopId)) return schedCache.get(stopId);
  const p = join(GTFS, "schedule", `${stopId}.json`);
  const s = existsSync(p) ? JSON.parse(readFileSync(p)) : null;
  schedCache.set(stopId, s);
  return s;
}
const svcCache = new Map();
function active(dateISO) {
  if (!svcCache.has(dateISO)) svcCache.set(dateISO, activeServices(dateISO));
  return svcCache.get(dateISO);
}

let matched = 0, noScheduleEntry = 0, noMatchInTol = 0;
const perLine = {};       // line -> {matched, unmatched}
const dist = { "79": [], "55": [] }; // delay seconds arrays for the two lines
const buckets = new Map(); // "line dir dow hour" -> {line,dir,dow,hour,count,sum}

for (const a of arrivals) {
  const sched = loadSched(a.stop_id);
  const pl = (perLine[a.line] ??= { matched: 0, unmatched: 0 });
  if (!sched) { noScheduleEntry++; pl.unmatched++; continue; }
  const d = new Date(a.observed_at * 1000);
  const ctx = belgradeNow(d);
  const act = active(ctx.dateISO), yest = active(ctx.yesterdayISO);
  const mins = [];
  for (const dep of sched.deps) {
    if (dep.line !== a.line) continue;
    if (a.dir !== "" && dep.route_id !== a.dir) continue;
    for (const [svc, m] of Object.entries(dep.svc)) {
      if (act.has(svc)) for (const t of m) mins.push(t);
      if (yest.has(svc)) for (const t of m) if (t >= OVERNIGHT) mins.push(t);
    }
  }
  if (mins.length === 0) { noScheduleEntry++; pl.unmatched++; continue; }
  const delay = schedDelaySeconds(ctx.minutes, mins);
  if (delay === null) { noMatchInTol++; pl.unmatched++; continue; }
  matched++; pl.matched++;
  if (dist[a.line]) dist[a.line].push(delay);
  const key = `${a.line} ${a.dir} ${d.getUTCDay()} ${d.getUTCHours()}`;
  let b = buckets.get(key);
  if (!b) buckets.set(key, (b = { line: a.line, dir: a.dir, dow: d.getUTCDay(), hour: d.getUTCHours(), count: 0, sum: 0 }));
  b.count++; b.sum += delay;
}

const total = arrivals.length;
const pct = (n) => `${((n / total) * 100).toFixed(1)}%`;
console.log("=== sched_delay match quality (staging, 69,972 arrivals) ===");
console.log(`matched:            ${matched.toLocaleString()} (${pct(matched)})`);
console.log(`unmatched TOTAL:    ${(total - matched).toLocaleString()} (${pct(total - matched)})`);
console.log(`  no schedule/line at stop: ${noScheduleEntry.toLocaleString()} (${pct(noScheduleEntry)})`);
console.log(`  no trip within ±30min:    ${noMatchInTol.toLocaleString()} (${pct(noMatchInTol)})`);

function summarize(line) {
  const xs = dist[line].slice().sort((a, b) => a - b);
  if (xs.length === 0) return console.log(`\nline ${line}: no matched arrivals`);
  const mean = xs.reduce((s, x) => s + x, 0) / xs.length / 60;
  const med = xs[Math.floor(xs.length / 2)] / 60;
  const p90 = xs[Math.floor(xs.length * 0.9)] / 60;
  const bins = [[-1e9,-5],[-5,-2],[-2,-1],[-1,1],[1,2],[2,5],[5,10],[10,20],[20,1e9]];
  const labels = ["<-5","-5..-2","-2..-1","on-time","1..2","2..5","5..10","10..20",">20"];
  const counts = bins.map(([lo,hi]) => xs.filter((x) => x/60 >= lo && x/60 < hi).length);
  console.log(`\nline ${line}: matched=${xs.length}  mean=${mean.toFixed(1)}min  median=${med.toFixed(1)}min  p90=${p90.toFixed(1)}min`);
  console.log("  delay(min):  " + labels.map((l,i) => `${l}:${counts[i]}`).join("  "));
}
summarize("79");
summarize("55");

// Emit UPSERT SQL to populate staging sched_delay_* (additive).
const stmts = [...buckets.values()].map((b) =>
  `INSERT INTO agg_line_dir_time (line,direction_route_id,dow,hour,sched_delay_count,sched_delay_secs_sum,updated_at) ` +
  `VALUES ('${b.line.replace(/'/g,"''")}','${b.dir.replace(/'/g,"''")}',${b.dow},${b.hour},${b.count},${b.sum},strftime('%s','now')) ` +
  `ON CONFLICT(line,direction_route_id,dow,hour) DO UPDATE SET ` +
  `sched_delay_count=sched_delay_count+excluded.sched_delay_count, ` +
  `sched_delay_secs_sum=sched_delay_secs_sum+excluded.sched_delay_secs_sum, updated_at=excluded.updated_at;`);
writeFileSync("/tmp/sched_writeback.sql", stmts.join("\n") + "\n");
console.log(`\nwrote ${stmts.length} UPSERTs -> /tmp/sched_writeback.sql`);
