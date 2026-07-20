#!/usr/bin/env node
// PHASE-0: final sweep profile for the OWNER'S chosen start tempo.
//   day   05:00–01:00 (20h): 1 sentinel / 20s  = 3 sweeps/min
//   night 01:00–05:00 ( 4h): paused
//   set: 163 sentinels (minimal, 1 per line×direction)
// Pure arithmetic; empirical constants measured from stigla-analytics 2026-07-20.

const N = 163;                    // sentinel stops (minimal set)
const DAY_RATE_PER_MIN = 3;       // 1 / 20s
const DAY_HOURS = 20;             // 05:00–01:00
const NIGHT_HOURS = 4;            // 01:00–05:00 paused

// --- measured constants ---
const ROWS_PER_SWEEP = 8;         // sentinels are busy multi-line mid-route stops; daytime 7–10, use 8
const ORGANIC_ROWS_DAY = 41016;   // current demand-driven write rate (rows/day), unchanged by the sweep
const BYTES_PER_ROW = 140;        // 55.37 MB / 399.8k rows incl. 4 indexes
const RETENTION_DAYS = 30;
const AGG_SCANS = 6;              // full-table scans the daily recompute does (3 line + 3 vehicle)
const REQ_PER_MIN_PER_USER = 2;   // prod hot key = 1 req/30s

// D1 FREE tier limits
const FREE_WRITES_DAY = 100_000;
const FREE_READS_DAY = 5_000_000;
const FREE_STORAGE_GB = 5;

// Adaptive skip: empirically ≤14/163 sentinels saw ANY organic traffic in 24h;
// within one ~1h cycle far fewer. Model a modest 5% daytime skip; night ~0.
const ADAPTIVE_SKIP = 0.05;

const cycleMin = N / DAY_RATE_PER_MIN;
const sweepsDayGross = DAY_RATE_PER_MIN * 60 * DAY_HOURS;
const sweepsDayNet = Math.round(sweepsDayGross * (1 - ADAPTIVE_SKIP));
const sweepRowsDay = Math.round(sweepsDayNet * ROWS_PER_SWEEP);
const totalWritesDay = sweepRowsDay + ORGANIC_ROWS_DAY;

const steadyRows = Math.round(totalWritesDay * RETENTION_DAYS);
const steadyMB = (steadyRows * BYTES_PER_ROW) / 1e6;
const aggReadsDay = steadyRows * AGG_SCANS;

const pct = (x) => `${(x * 100).toFixed(0)}%`;
const ok = (v, lim) => (v <= lim ? "✓ FITS" : "✗ OVER");

console.log("=== FINAL SWEEP PROFILE — start tempo (day 1/20s, night 01–05 pause) ===\n");
console.log(`sentinels:                    ${N} (minimal, 1 / line-dir)`);
console.log(`daytime rate:                 ${DAY_RATE_PER_MIN}/min  (0.05/s)`);
console.log(`full-city cycle (day):        ${cycleMin.toFixed(0)} min`);
console.log(`equiv. concurrent users:      ~${(DAY_RATE_PER_MIN / REQ_PER_MIN_PER_USER).toFixed(1)} (vs prod hot key = 2 req/min/user)\n`);

console.log("--- SOURCE-FACING LOAD ---");
console.log(`sweep requests/day (gross):   ${sweepsDayGross.toLocaleString()}`);
console.log(`  after adaptive skip (~${pct(ADAPTIVE_SKIP)}):  ${sweepsDayNet.toLocaleString()}`);
console.log(`night (01–05):                0 (paused)\n`);

console.log("--- D1 WRITES / day ---");
console.log(`sweep rows (@${ROWS_PER_SWEEP}/sweep):         ${sweepRowsDay.toLocaleString()}`);
console.log(`organic rows (unchanged):     ${ORGANIC_ROWS_DAY.toLocaleString()}`);
console.log(`TOTAL raw writes/day:         ${totalWritesDay.toLocaleString()}   ` +
  `${ok(totalWritesDay, FREE_WRITES_DAY)} free tier (${FREE_WRITES_DAY.toLocaleString()}/day), ` +
  `headroom ${pct(1 - totalWritesDay / FREE_WRITES_DAY)}\n`);

console.log("--- D1 STORAGE (30-day steady state) ---");
console.log(`raw rows retained:            ${steadyRows.toLocaleString()}`);
console.log(`raw size:                     ${steadyMB.toFixed(0)} MB   ` +
  `${ok(steadyMB / 1000, FREE_STORAGE_GB)} free tier (${FREE_STORAGE_GB} GB)\n`);

console.log("--- D1 READS / day (daily aggregate = full recompute, ~" + AGG_SCANS + " scans) ---");
console.log(`rows read/day:                ${aggReadsDay.toLocaleString()}   ` +
  `${ok(aggReadsDay, FREE_READS_DAY)} free tier (${FREE_READS_DAY.toLocaleString()}/day)`);
console.log(`  NOTE: organic-only at steady state already reads ~` +
  `${(ORGANIC_ROWS_DAY * RETENTION_DAYS * AGG_SCANS / 1e6).toFixed(1)}M/day — the full-recompute`);
console.log(`  aggregate breaches the free READ ceiling regardless of the sweep.`);
console.log(`  FIX: incremental aggregate (read only raw since last_run) → ~` +
  `${(totalWritesDay * 2 / 1e6).toFixed(2)}M/day, well under free. Or Workers Paid (25B reads/mo).`);
