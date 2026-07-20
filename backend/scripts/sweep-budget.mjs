#!/usr/bin/env node
// PHASE-0: sweep budget table. Pure arithmetic over the sentinel count and a
// few empirical constants pulled from the live analytics D1 (documented below).
// No source calls, no D1 access here.

// --- Sentinel counts from build-sentinels.mjs ---
const N_MIN = 163; // 1 sentinel / line-dir (greedy reuse), covers 453 line-dirs
const N_RED = 336; // 2 sentinels / line-dir (redundant)

// --- Empirical constants (measured from stigla-analytics, 2026-07-20) ---
// avg rows written per arrivals refresh: 24h equal-weighted mean of hourly
// means = 5.86; daytime service hours run 7–9. Use 7 as a planning midpoint.
const ROWS_PER_REFRESH = 7;
// bytes per raw row incl. 4 indexes: size_after 55.37 MB / 399.8k rows ≈ 138 B.
const BYTES_PER_ROW = 140;
const RETENTION_DAYS = 30;
// Prod background rate on a hot key: 1 refresh / 30s = 2 req/min per active user.
const REQ_PER_MIN_PER_USER = 2;

const cycles = [10, 20, 30];

function row(label, N, C) {
  const perMin = N / C; // sentinels swept per minute = source req/min (gross)
  const perSec = perMin / 60;
  const users = perMin / REQ_PER_MIN_PER_USER; // equiv. concurrent active users
  const sweepsPerDay = N * (1440 / C);
  const rowsPerDay = sweepsPerDay * ROWS_PER_REFRESH;
  const steadyMB = (rowsPerDay * RETENTION_DAYS * BYTES_PER_ROW) / 1e6;
  const batchPerMin = Math.ceil(N / C); // sentinels per 1-min cron invocation
  return { label, C, perMin, perSec, users, sweepsPerDay, rowsPerDay, steadyMB, batchPerMin };
}

function fmt(r) {
  return (
    `| ${r.label} | ${r.C} min | ${r.batchPerMin}/min | ` +
    `${r.perMin.toFixed(1)} (${r.perSec.toFixed(2)}/s) | ` +
    `~${r.users.toFixed(1)} users | ` +
    `${Math.round(r.sweepsPerDay).toLocaleString()} | ` +
    `${Math.round(r.rowsPerDay).toLocaleString()} | ` +
    `${r.steadyMB.toFixed(0)} MB |`
  );
}

console.log("Sentinel set: MINIMAL = 163 stops, REDUNDANT = 336 stops");
console.log("Assumptions: rows/refresh=7, bytes/row=140, retention=30d, 1 user=2 req/min\n");
console.log("| Set | Full cycle | Cron batch | Source req/min | Equiv. load | Sweeps/day | D1 rows/day | D1 steady-state |");
console.log("|-----|-----------|-----------|----------------|-------------|-----------|-------------|-----------------|");
for (const C of cycles) console.log(fmt(row("minimal (163)", N_MIN, C)));
for (const C of cycles) console.log(fmt(row("redundant (336)", N_RED, C)));

console.log("\nBaseline for comparison: prod hot key = 2 req/min (0.033/s) per active user.");
console.log("SWR dedup: a sweep that lands on a stop already hot from a user is a cache");
console.log("hit (free). Sentinels are spread citywide, so daytime overlap is small (~a");
console.log("few of 163); night overlap ~0. Numbers above are the gross (no-dedup) upper bound.");
