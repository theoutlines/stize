# Citywide sweep & analytics v2 — design

How Stigla builds a **citywide** history of how Belgrade's transit actually runs —
reliability, typical headways, "how it usually is at this hour", punctuality vs
the timetable — while touching the live data source only **gently**, as a slow
background trickle that always yields to real user traffic.

This is a design document for people. It explains what the system does, which
signals it uses, and why each decision was made.

---

## 1. The problem: demand-driven history is biased

Stigla logs what it already fetches to serve you. When you open a stop, the live
board it shows is also recorded as observations (line, vehicle, how far away,
when). That was enough to prototype the analytics screens, but it has a built-in
bias: **history only exists for the stops people actually open.**

Measured on the live history (≈400k observations over ~10 days): the top 13 lines
account for **83%** of all rows, and the 8 busiest stops — two commuter corridors —
for **58%**. Of ~470 lines in the schedule, only ~90 had enough history to be
useful; the rest were empty. Even a "well covered" line was only sampled on the
handful of stops near where people boarded it, not along its whole length.

To show reliable, unbiased analytics for **every** line, we need to observe the
whole network — not just the busy stops — without turning that into a heavy,
constant pull on the upstream data.

---

## 2. The sentinel sweep

### 2.1 The key observation

One stop's arrivals response carries **every vehicle currently heading to that
stop** — each with its position, id, and remaining route. So a single well-placed
stop in the **middle of a line** observes essentially that line's whole active
fleet in one request. We call such a stop a **sentinel**.

That turns "watch the whole city" from *thousands of stops* into *a few hundred
sentinels* — one or two per line-and-direction, mostly reused across lines.

### 2.2 Choosing the sentinels

Built from the static GTFS bundle (`scripts/build-sentinels.mjs`), no network
involved:

- For each line×direction, the eligible sentinels are the stops in the **middle
  third** of the route — a mid-route stop sees the most vehicles at once.
- A **greedy minimum-set-cover** then picks the fewest stops that still cover
  every line×direction, preferring stops that sit mid-route on several lines.

Result: **163 sentinels** cover all **453** city line×directions (2.78 covered per
stop). The list ships as a static asset (`public/gtfs/sentinels.json`), rebuilt
whenever the GTFS bundle is.

### 2.3 A gentle, background tempo

The sweep is a once-a-minute Cron job that walks the sentinel list on a slow
rotation, reusing the **same cached read path** as normal user requests — so a
sweep that lands on a stop someone is already viewing costs nothing (it's a cache
hit), and the source only ever sees a slow, even trickle.

The pace is the one thing that reaches the source, so it lives entirely in two
runtime settings (no redeploy) and is deliberately conservative:

- **daytime:** one sentinel every 20 seconds (≈3/minute → a full city cycle in
  ~54 minutes) — a load comparable to *a couple of* people using the app at once;
- **night (01:00–05:00 Belgrade):** paused — little service runs then, so there's
  little to observe and no reason to poll;
- raised slowly over time only if everything stays healthy.

Two more safeguards keep it polite:

- **Adaptive skip.** If organic user traffic already refreshed a sentinel within
  the current cycle, the sweep skips it — the data's already fresh, so re-fetching
  would add nothing. In practice only a small fraction of sentinels overlap user
  traffic, so this quietly lowers the real footprint below the nominal pace.
- **Automatic back-off.** User traffic always matters more than analytics. If the
  source starts returning trouble instead of clean data, the sweep **stops itself**
  (a single setting flip, no redeploy) and signals for a human to look — rather
  than keep pulling. It only resumes when re-enabled.

Everything the sweep records goes through the **existing** observation path — no
new kind of request to the source, and the same cache keys as user traffic.

---

## 3. Analytics data model (v2)

Raw observations are rolled up by a daily job into compact, long-lived aggregates.
Raw rows are kept for a rolling 30 days; the aggregates persist.

### 3.1 Per line × direction × day-of-week × hour

The core table (`agg_line_dir_time`) holds, for each line, direction, weekday and
hour:

- **activity & arrivals** — how much service was seen;
- **real headways** — measured gaps between successive vehicles at a stop;
- a **headway histogram** — 12 fixed buckets of the interval distribution, so any
  percentile ("median wait", "90th-percentile wait") is derivable, and "today is
  worse than usual" is a comparison against the stored distribution, not just a
  mean;
- **speed** — route progress rate (stops closed per minute);
- **schedule delay** — see §3.3.

Splitting by **direction** matters because a line's two directions can behave very
differently (peak flow one way). The direction is resolved the same way the map
resolves it, from each vehicle's own route geometry.

Why a **histogram** rather than a stored average? An average hides the shape. A
histogram is additive and mergeable across time, supports any percentile after the
fact, and is the honest foundation for the "as-usual" baseline that later powers
the "worse than usual" badge, coverage weighting, and arrival predictions.

### 3.2 Per vehicle

A parallel per-vehicle rollup records which vehicle runs which line, its own
punctuality, and its first/last-seen dates — the raw material for fleet features
(which model you're about to board, roster changes over time).

### 3.3 Schedule delay (punctuality vs the timetable)

For each observed **arrival**, the aggregate finds the nearest scheduled departure
of that line/direction at that stop — using the GTFS timetable and the service
calendar for that date, in Belgrade local time, across the midnight wrap — and
records the signed delay (late = positive). Accumulated as count + sum per bucket,
so per-line/hour mean punctuality falls out directly.

Measured over the staging history (≈70k arrivals): **~82% of arrivals matched a
scheduled trip**; of the unmatched ~18%, almost all were cases where the timetable
simply has **no entry for that line at that stop** (night/suburban variants, or
stops where the live line label differs from the schedule's) — only **0.1%** had a
timetable but no trip within tolerance. In other words the matcher is sound, and
the "unmatched" fraction is itself a useful **data-quality signal** that citywide
collection surfaces. For a well-scheduled line (79), 100% of arrivals matched, with
a median delay of ~0 and a 90th percentile of ~4 minutes.

### 3.4 Incremental aggregation (why the daily job stays cheap)

Recomputing every aggregate from all raw each day would read the whole table
repeatedly. Instead the job is **incremental**: it reads only observations newer
than its last run (plus a short lookback so a headway/speed pair straddling the
boundary is still computed correctly) and **adds** their contributions to the
existing buckets. Counts are additive; first/last-seen take min/max; the histogram
buckets add elementwise. A watermark makes it idempotent — re-running immediately
does nothing.

Measured effect (staging, ~340k rows): a one-time full backfill reads ~4.1M rows;
a **daily incremental run reads ~0.14M** — about **30× less**, and comfortably
inside routine limits — while producing identical aggregates.

---

## 4. What this unblocks

- **"How it usually is at this hour"** baselines for every line — the foundation
  for a "today is worse than usual" badge, smarter coverage weighting, and arrival
  predictions.
- **Reliability by line and by vehicle/model**, from citywide (not corridor-biased)
  history.
- **Faster, fairer** ghost-line and roster analysis, since history accumulates for
  the whole network instead of only where a few people ride.

---

## 5. Operational notes

- The sweep is behind a runtime flag, **off by default in production**, and is the
  killswitch (also flipped off automatically by the back-off above).
- Tempo is two runtime settings (day / night interval); no redeploy to change.
- Draft line-analytics screens read the same per-line endpoint and light up for any
  line as its history fills — no screen changes are part of this work.
- Client polling and user-facing request paths are untouched; analytics writes ride
  along on work already done and never block a response.
