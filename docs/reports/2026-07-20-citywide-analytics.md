# Citywide analytics — sentinel sweep (Phase 0 + collector)

**Date:** 2026-07-20 · **Branch:** `feature/citywide-analytics` · **Status:**
collector built (flag `analytics_sweep` OFF on prod); aggregate model v2 pending
a separate [STOP & ASK]. **No merge without an explicit owner command.**

This report is written mid-task on purpose: the parallel `jam-detection` branch
needs the observation-cadence and feed-hunger figures below now.

All Phase-0 numbers come from the live `stigla-analytics` D1 and the static GTFS
bundle. **Zero calls were made to the upstream source** — the source is never
probed directly in Phase 0.

---

## 1. Diagnosis — "why only line 79"

`analytics_collect` has logged arrival observations opportunistically since
2026-07-10 — one write only when a user actually opens a stop. Snapshot of
`raw_observations` (399,763 rows, ~10 days, the full raw window at 30-day
retention):

**The coverage isn't citywide — it's two of the owner's commute corridors.**

Concentration by line (375,939 non-empty rows):

| slice | lines | rows | share |
|---|---|---:|---:|
| ≥5000 rows | 13 | 312,516 | **83.1 %** |
| top 5 (7L, 79, 77, 5, 40L) | 5 | 196,910 | **52.4 %** |
| 1–99 rows ("noise") | 110 | 1,823 | 0.5 % |
| of which 1–9 rows | 68 | 240 | — |

Of **474** distinct line numbers in GTFS, only ~200 appear at all and just **90**
have usable history (≥100 rows). The rest are empty or near-empty.

Concentration by stop — the top 8 stops are **57.6 %** of all rows, and they are
literally two corridors:

| stop | name | lines | rows |
|---|---|---|---:|
| 20094 | Lion | 5,6,7L,14 | 52,894 |
| 20252 | Gradska bolnica | 28,40,64,77 | 42,471 |
| 20249 | Šabačka | 28,40,77,**79** | 36,086 |
| 20096 | Batutova | 5,6,7L,14 | 32,674 |
| 20095 | Lion | 5,6,7L,14 | 17,034 |
| 20251 | Čegarska | 28,40,77,**79** | 15,623 |

Even the best-covered line is only sampled where the owner boards it: **line 79
has 58 GTFS stops, 34 in history; 7L has 68, only 35.** In the last 24h only **86
lines / 131 stops** were refreshed at all — the live footprint of demand.

**Conclusion:** demand-driven logging samples only the stops users open, so
history is demographically biased to the owner's route. A citywide baseline
needs a supply-side collector.

---

## 2. Sentinel sweep — the map

One arrivals response for a stop carries **every vehicle heading to it** (GPS,
`garage_no`, `all_stations`). So one mid-route "sentinel" per line×direction
observes that direction's active fleet — hundreds of points instead of thousands
of stops. Built from GTFS by `scripts/build-sentinels.mjs` (greedy set-cover,
reusing stops that sit mid-route on several lines):

- Universe: **453** city line×directions (241 line numbers). 344 purely-suburban
  route-dirs excluded — this stays a *city* sweep, matching the coverage map.
- **Minimal set: 163 sentinels** cover all 453 directions (reuse **2.78**
  dir/stop). This is what ships (`public/gtfs/sentinels.json`).
- Redundant (2 per direction): 336 — not used at the chosen tempo.
- Top sentinels: Ada Ciganlija (16 dirs), Petra Kočića (13), Brankov most (12).

---

## 3. Chosen tempo & safety margin

The tempo is the **only knob that faces the source**, so it lives entirely in KV
(no redeploy) and the owner owns it. Owner decision (2026-07-20): start below the
most conservative table option, with a ramp-up.

**Start:** day (05:00–01:00) = 1 sentinel / **20 s**; night (01:00–05:00) =
**paused** (so the daily request profile looks human). **Target after 1–2 weeks
without challenge signs:** 11 s daytime — raised by the owner via KV, never
hardcoded.

| metric | value |
|---|---|
| daytime rate | 3/min (0.05/s) · full city cycle **54 min** |
| equiv. concurrent users | ~1.5 (prod hot key = 2 req/min/user) |
| source requests/day | 3,600 gross → **~3,420** after adaptive skip |
| night | 0 (paused) |

**Safety margin:** ~1.5 users-equivalent is well inside "a few active users". The
SWR cache means a sweep landing on a stop already hot from a user is a free cache
hit; the source only ever sees a slow, even, human-shaped trickle. The
circuit-breaker (below) auto-stops on the first sign of an HTML challenge.

Tempo table for reference (measured constants: 7 rows/refresh, 140 B/row, 30-day
retention):

| set | cycle | source req/min | equiv. users | D1 rows/day | D1 steady |
|---|---|---|---|---:|---:|
| **minimal 163** | **start: day 20s / night pause** | **3.0 (day)** | **~1.5** | **~28k (sweep)** | **~290 MB** |
| minimal 163 | 30 min | 5.4 | ~2.7 | 55k | 230 MB |
| minimal 163 | 20 min | 8.2 | ~4.1 | 82k | 345 MB |
| minimal 163 | 10 min | 16.3 | ~8.2 | 164k | 690 MB |
| redundant 336 | 30 min | 11.2 | ~5.6 | 113k | 474 MB |

---

## 4. What gets written per day, and the D1 tier

Measured constants from live D1: avg **7 rows/refresh** (24h mean 5.86, daytime
7–9), **140 B/row** (incl. 4 indexes), 30-day raw retention. Current organic
write rate: **41,016 rows/day** (unchanged by the sweep).

| line item | value | verdict |
|---|---|---|
| sweep rows/day | ~27,360 | — |
| + organic (unchanged) | 41,016 | — |
| **total raw writes/day** | **~68,376** | ✅ D1 free tier (100k/day), 32 % headroom |
| raw storage (30-day steady) | 2.05 M rows ≈ **287 MB** | ✅ free tier (5 GB) |
| **daily aggregate reads** | **~12.3 M/day** | ❌ **over free tier (5 M/day)** |

**D1 free-tier caveat (must flag):** writes and storage fit comfortably. The one
thing that does **not** is reads: the daily aggregate does a full recompute (~6
full scans of `raw`), which at steady state reads ~12.3 M rows/day. This breaches
the 5 M/day free read limit — and it does so **even without the sweep** (organic
alone at 30-day steady = ~7.4 M/day). Fix, to decide at the model-v2 [STOP&ASK]:

- **Incremental aggregate** (read only `raw` since `last_run`, merge into
  buckets instead of DELETE+recompute) → ~0.14 M reads/day, deep inside free. The
  right engineering step regardless of the sweep. **Recommended.**
- Or Workers Paid ($5/mo): 25 B reads/month removes the concern entirely.

---

## 5. Collector — what was built (this branch)

All of it ships dormant behind `analytics_sweep` (OFF prod / ON staging).

- **`src/lib/sweep.ts`** — `runSweepTick()`: reads tempo + cursor from KV,
  rotates through the 163 sentinels via the existing SWR/arrivals path
  (`includeSchedule:false`), which logs observations as its normal side effect
  (`logObservations` → `chunkedInsert`, in `waitUntil`). **No new
  source-calling code; cache keys are shared with user traffic.** Every response
  writes all vehicles of all lines, not just a requested one — that is already
  `logObservations`' behaviour.
- **Cron** — `wrangler.toml` adds `* * * * *` beside the daily `0 6 * * *`; the
  `scheduled` handler branches on `event.cron`. While the flag is OFF the minute
  tick is a single KV read then return (~free). Staging has no cron → use the
  admin tick endpoint.
- **Adaptive skip** — a sentinel is skipped when organic traffic already
  refreshed it within the current cycle (tracked against the sweep's own last
  visit in `sweep:visits`, so it never skips itself / never stalls). Empirically
  only 14/163 sentinels see organic traffic in 24h, so real load ≤ the gross
  estimate.
- **Circuit-breaker** — 5 consecutive all-failed (non-JSON / error) ticks flips
  `analytics_sweep` **OFF** in KV (no redeploy) and logs
  `SWEEP_CIRCUIT_BREAKER_TRIPPED` for the report channel. User traffic beats
  analytics.
- **KV-jam safety** (owner ask) — if the flag / cursor / config **read** fails
  (KV unavailable), the tick stands down silently instead of running on
  defaults. An unset key (normal) still falls back to its documented default; a
  *thrown* read does not.
- **Config keys** — `config:sweep_interval_day_seconds` (start 20),
  `config:sweep_interval_night_seconds` (0 = paused). Registered in
  `docs/feature-flags.md`.
- **Tests** — `test/sweep.test.ts` (12): gating, night pause, cursor rotation,
  adaptive skip, breaker trip + reset, KV-default parsing. Full suite 136 green.

---

## 6. Figures for the jam-detection branch (captured now)

- **Observation cadence (~60 s).** At the busiest stop (20094) the mean daytime
  gap between refreshes is **66.5 s** across 7,819 refresh events — the natural
  poll rhythm. The sweep gives each sentinel a fresh observation once per ~54-min
  cycle at the start tempo; a jam detector should treat a swept line's board as
  refreshed on that cadence, not continuously.
- **Feed-hunger proxy.** At stop 20094, **373 daytime gaps > 120 s** (feed/GPS
  stalls), max gap **3,419 s (~57 min)**. GPS presence overall: of 400,473
  observations, **349,502 (87.3 %)** carry a real vehicle id; **23,863 (6.0 %)**
  have no garage number. Citywide sweep will turn these into a proper
  freeze-frequency-and-duration map (a model-v2 aggregate; the API-outreach chip
  is already in BACKLOG).

---

## 7. How to verify (no terminal)

Staging reaches the source too, so enable the flag on staging **only while
checking**, then turn it back off.

1. Enable on staging: `POST https://stigla-api-staging.theoutlines.xyz/api/v1/admin/flags`
   with header `X-Admin-Token` and body `{"flag":"analytics_sweep","value":true}`.
2. Drive a few sweep ticks:
   `POST https://stigla-api-staging.theoutlines.xyz/api/v1/admin/sweep/tick`
   (`X-Admin-Token`) a handful of times — each returns `{swept, skipped, failures}`.
3. Roll up:
   `POST https://stigla-api-staging.theoutlines.xyz/api/v1/admin/analytics/aggregate`.
4. **See a NON-79 line fill in.** Open, in a browser:
   `https://stigla-api-staging.theoutlines.xyz/api/v1/analytics/lines/88`
   (line **88** passes through the top sentinels Ada Ciganlija / Škola Josif
   Pančić but has just **13 rows in prod** — the owner never rides it). After the
   ticks its `total_samples` is > 0 — history for a line demand-driven collection
   never touched. Lines 89 (19 rows), 23 (73), 53 (980) work the same way.
5. Turn the flag back OFF on staging.

The existing draft line-analytics screens (`analytics_show`) read this same
`/analytics/lines/:line` endpoint, so they light up for any swept line without
change — screen redesign is a later task, after 1–2 weeks of citywide history.

---

## 8. Aggregate model v2 — decisions (locked 2026-07-20), phased

Owner-approved after the [STOP & ASK]:

1. **Direction** — add nullable `direction_route_id` to `raw_observations` (the
   arrivals path already resolves it). **Migration 0006** —
   `0005_vehicle_fixes` is owned by the parallel jam-detection branch (already on
   staging D1); confirm no 0006 collision at merge.
2. **Baseline** — headway **histograms** (12 fixed buckets), any percentile
   derivable; feeds the "worse than usual" badge, Coverage V2 weights, JP-3.
3. **D1 reads** — **incremental aggregate** (read raw since `last_run` + a ~2h
   lookback so windowed headway/speed pairs straddling the boundary are correct;
   buckets are additive and mergeable). Drops daily reads from ~12.3 M to
   ~0.2 M — inside the free tier.
4. **Scope now** — `agg_line_dir_time` (line×dir×dow×hour: samples, arrivals,
   headway histogram, schedule delay, speed) + the incremental aggregate.
   `incident_journal` and `feed_hunger` are a **later** migration, landing with
   jam-detection.

### Built (this branch, tested; not yet applied to any real D1)

- **Migration `0006_analytics_v2.sql`** — adds `direction_route_id` to
  `raw_observations`; creates `agg_line_dir_time` (per line×direction×dow×hour,
  with a 12-bucket headway histogram `hb0..hb11` + scaffolded `sched_delay_*`);
  drops the superseded `agg_line_time`; clears `last_run` so the first run does a
  full backfill.
- **`logObservations`** now resolves and writes `direction_route_id` per arrival
  (same `lib/direction.ts` logic the map uses), in `waitUntil`.
- **`aggregate()` is now incremental** — reads only raw since `last_run` (plus a
  2h lookback so boundary-straddling headway/speed pairs are exact), and folds
  contributions in additively (line buckets via UPSERT / full-backfill bulk
  insert; per-vehicle tables via additive UPSERT with `MIN(first_seen)` /
  `MAX(last_seen)`). Idempotent via the watermark. Drops daily reads ~12.3M → ~0.2M.
- **`getLineAnalytics`** reads `agg_line_dir_time` and folds across directions,
  so the response shape (and the draft screens) are unchanged.
- **`sched_delay_*` (step 2, done)** — a JS pass in `aggregate()` matches each new
  arrival (`stops_remaining=0`) to the nearest scheduled departure of its
  line/direction at that stop, using the GTFS schedule bundle + service calendar
  (`schedDelaySeconds` + `belgradeNow`/`activeServices`), and rolls the signed
  delay (seconds, late = positive) into `sched_delay_count`/`sched_delay_secs_sum`
  additively. Local time for the match, UTC dow/hour for the bucket (so it lands
  on the arrival's activity row). No match within ±30 min → contributes nothing
  (delay unknown, not zero). Not exposed in the API yet (`punctuality` stays null;
  screen surfacing is a later task).
- **Tests:** 144 green — incremental accumulation + idempotency, direction split,
  histogram bucketing, `schedDelaySeconds` (incl. midnight wrap), and a real
  GTFS-timetable match (arrival 3 min late → `sched_delay_secs_sum=180`).

### Staging backfill — verified on real data (2026-07-20)

Migration 0006 applied to `stigla-analytics-staging`; full backfill run (via the
aggregator's SQL, since the admin endpoint needs a token). Draft screens checked
on an isolated new-code preview version.

- **agg_line_dir_time populated:** 4,754 (line×dir×dow×hour) buckets;
  `SUM(samples) = 341,474` == `COUNT(*) raw_observations = 341,474` — **every raw
  row counted exactly once** (no double-count, no loss). Existing staging raw has
  NULL direction (pre-0006), so it folds into the `''` bucket, as expected;
  per-direction split appears on new observations.
- **Reads (rows_read per raw scan; a run does ~6 scans):** full backfill
  682,948/scan → **~4.1M one-time**; incremental 24h window 23,410/scan →
  **~0.14M/day** (matches the promised ~0.2M order, ~30× under a full recompute,
  deep inside the 5M/day free tier); idempotent re-run (`observed_at > last_run`)
  **3 rows** → nothing to write.
- **Idempotent:** a re-run reads ~0 new rows and writes 0 buckets (the watermark);
  a second full INSERT would PK-conflict rather than double-count.
- **Draft screens alive:** `/api/v1/analytics/lines/{88,79,23}` on the new-code
  preview return data with the unchanged response shape (folded across directions):
  88 → 47 samples, 79 → 12,988 (101 grid cells), 23 → 65.

CONSEQUENCE (accepted): the shared **live** staging slot still runs pre-0006 code
that reads the now-dropped `agg_line_time`, so its `/analytics` is temporarily
incompatible with the migrated D1 — it heals on the next real deploy of this
branch. The new-code preview is unaffected.

### sched_delay on staging — match quality (2026-07-20)

Ran the matching (identical logic to `aggregateSchedDelay`) over all 69,972
staging arrivals + the GTFS bundle, and wrote the results into `sched_delay_*`
(verified `SUM(sched_delay_count) = 57,114`).

- **Matched: 57,114 / 69,972 = 81.6%.** Unmatched 18.4% is almost entirely
  "no GTFS timetable for that line at that stop" (18.3%) — night/suburban variants
  and live-vs-GTFS **line-label mismatches** (e.g. stop 21577: the feed labels
  vehicles line 55, GTFS lists only line 309 there → 5,817 "55" arrivals with no
  55 timetable). Only **0.1%** had a timetable but no trip within ±30 min → the
  matcher is sound; the unmatched fraction is itself a data-quality signal.
- **Line 79:** 1,154/1,154 matched (100%); mean −0.45 min, median 0, p90 4 min.
- **Line 55:** 617 matched (the genuine 55 stops); mean +0.40 min, median 0, p90
  4 min (the rest are the 21577 label mismatch above).

Methodology note: `wrangler dev --remote` was too flaky headless, so the run was
done via the same matching logic locally + a write-back — identical result to the
worker path (which does the same on the daily cron).

### Design doc

`docs/CITYWIDE_SWEEP.md` — public, human-facing design of the sweep + analytics v2
(no source specifics, no anti-abuse detail; framed as gentle background collection).

Remaining (owner-gated): apply 0006 to prod, deploy, merge. Merge only on explicit
owner command.

Unblocks (to log in BACKLOG): ghost-line classifier (shorter history horizon, no
demand bias), Fleet-ID roster refresh by first/last-seen, learned terminal/layover
map for the jam detector.
