# Stiže — Roadmap

Where the product is and where it's going. Status: ✅ shipped · 🚧 in progress /
behind a flag · ⏭️ next · 💡 idea · 🧊 icebox.

## Product frame

Stiže is **not a journey planner** (no A→B routing). It answers the two
questions a rider at a stop has: **what's coming and when**, and **which vehicle
am I about to board — and can I trust it?** Three pillars: **arrivals /
vehicles / reliability**. Priority ≈ how much a factor weighs in a rider's
decision × how cheap the data is × how independent it is of audience size. Data
that can't be collected retroactively, we start accumulating before we need it.

## Shipped

- Real-time map: stops, search, vehicle tracking with smooth movement along the
  route (extrapolation between fixes, GPS-anchored, "looks stuck" heuristic).
- **GPU vehicle rendering** — moving vehicles as a single batched MapLibre symbol
  layer (sub-linear in count), typed (bus / tram / trolleybus, with room for
  more), positioned by a backend timed trajectory and interpolated on the GPU.
- **Vehicle direction** — vehicles stitched to the shape of the direction
  they're actually travelling, not the canonical one.
- Inline route highlight on tapping a vehicle; type classification.
- Platform-adaptive UI (iOS Cupertino / Android Material / Web).
- **Fleet identification** — from a garage number, show the vehicle's model,
  class, age and comfort (A/C, low-floor, eco), with a model card and a
  comfort-based sort. Client-only, localized EN/RU/SR.
- **Schedule fallback** — the arrivals list backfills GTFS scheduled departures
  when live is thin (labeled "scheduled"), and the map shows scheduled vehicles
  where a line has no live one, moved by the same timed trajectory.
- **Nearby** — a location-first list of catchable lines around you (live +
  schedule, so nearby stops are never empty), ordered by time-to-board.
- **Coverage heatmap** on the main map when zoomed out (route density).
- **Suburban lines** that transit the city added to city stops.
- Feedback board and contextual line alerts.
- Background arrival-history collection (for future reliability metrics).
- **Vehicles on demand** (`vehicles_on_demand`, shipped to `main`+prod
  2026-07-16 **OFF** as a rollback switch) — with the flag ON the main map drops
  the background "aquarium" and shows vehicles only *in context*: the markers of
  a tapped stop's arrivals, and a *followed* vehicle (camera tracks it, breaks on
  a manual gesture), both fed from the already-loaded per-stop arrivals (no second
  fan-out). Ships alongside a **flag-free bugfix** (opening a vehicle from the
  arrivals list guarantees its marker + follow) and, this round, an honest
  arrivals list: `arrivalRowStatus` classifies every row as **live / expected /
  scheduled** (no blank rows; the placeholder class reads "Expected"), and
  **brightness = clickability** — live rows are full-opacity with a `›` chevron,
  non-clickable (Expected/Scheduled) are dimmed, same rule in the Nearby list.
  Backend carries the `swrCache` hard-stale (>40s → block on one fresh fetch) +
  single-flight fix. 6 rounds of owner acceptance; report
  `docs/reports/2026-07-15-vehicles-on-demand.md`.
- **Citywide sentinel sweep + analytics v2** (`feature/citywide-analytics`,
  **MERGED to `main` + in prod 2026-07-20**, `analytics_sweep` **ON prod**) —
  demand-driven collection only sampled the owner's two commute corridors (top 8
  stops = 57.6% of rows; of 474 GTFS lines only ~90 had usable history). The
  **sentinel sweep** fixes the bias from the supply side: **163 mid-route
  sentinels** (greedy set-cover) cover all 453 city line×directions, rotated by a
  minute Cron through the **existing SWR/arrivals path** — no new source-calling
  code, cache keys shared with user traffic. Tempo is the only knob facing the
  source and lives entirely in KV (`config:sweep_interval_day_seconds`, start 20s
  → target 11s; night paused so the daily request profile stays even and gentle);
  an **adaptive skip** drops sentinels organic traffic already refreshed, and an **auto
  circuit-breaker** flips the flag OFF after 5 consecutive failed ticks. **Analytics
  v2** (migration `0006`): `direction_route_id` added to `raw_observations` (in raw
  **only from 2026-07-20**), new `agg_line_dir_time` (line×dir×dow×hour with 12-bucket
  headway histograms), and an **incremental aggregate** (reads raw since `last_run`
  + a 2h lookback) that drops the daily D1 read from ~12.3M to ~0.2M — inside the
  free tier. **`sched_delay` best-effort**: each arrival matched to the nearest
  scheduled departure (81.6% match on staging; the 18.3% unmatched is a data-quality
  signal — feed↔GTFS line-label mismatches), rolled into `sched_delay_*` but **not
  yet exposed** (`punctuality` stays null; a later screen task). Design doc:
  `docs/CITYWIDE_SWEEP.md`. Report `docs/reports/2026-07-20-citywide-analytics.md`.

## In progress / behind a flag

- 🚧 **Rebrand Stigla → Stiže / stize.app** — branch `feature/rename-stize`,
  **NOT merged** (merges to `main` first, before JP-1). User-facing brand →
  `Stiže`, ASCII identifiers + Flutter package → `stize`; infra names `stigla-*`
  frozen (see `CLAUDE.md` → Naming). `stize.app` bound to Pages live;
  `api.stize.app` declared in `wrangler.toml` (binds on prod deploy). Deferred to
  prod-go: 301 old-domain + www→apex redirects, MapTiler `stize.app` origin.
  GitHub repo rename at task end. Full report:
  `docs/reports/2026-07-21-rename-stize.md`.
- 🚧 **Tram-jam ("stalled segment") detection** — **MERGED to `main` + in prod
  2026-07-20**, split like analytics: **recording ON prod** (`jam_detection_collect`),
  **UI behind a flag OFF prod** (`jam_detection_show`). Detects when a whole tram
  line stacks up on one stalled segment, paints that segment amber, and softly
  warns downstream stops of a possible delay. **Phase-0 measurement (12.5 min
  live)** proved the "everything frozen" surface signal is a **feed-starvation
  sawtooth** (upstream `updated_at` advances every ~60s; at 30s polling half the
  reads are re-stamps), not a jam — so the detector keys off a per-vehicle freeze
  clock that survives the sawtooth, gates on global feed health (all types frozen
  ⇒ suppress), and excludes terminals. **T_jam thresholds are PRELIMINARY** — no
  live jam was captured, only validated as "does not fire on starvation".
  Storage **Variant B**: a standalone `vehicle_fixes` last-fix table (migration
  `0005`, uncoupled from `raw_observations`) written opportunistically on the
  existing SWR refresh — no extra source calls — so a jam shows instantly on
  open; the `collect`/`show` split (added at merge) is what makes this true, since
  history must accrue *before* the UI ships. Backend `GET /api/v1/jams` does only
  cheap ordering; the client projects the amber segment onto the direction shape
  with a **geometry gate** (off-shape lines like 26/27/44 → no segment, degrade to
  affected-stop glow). Also: a bus-on-a-tram-line **substitution** notice
  (garage-no classifier, cross-checked against route alerts for tone). Round-2
  (owner-accepted): amber pulsing segment + affected-stop glow (thinner than the
  route, under the pins, cheap opacity pulse only while a jam is shown), off-shape
  lines get glow-only; jam-mode map toggle (fit to all jams) with a red count badge
  that lights up ONLY for context-relevant jams (near you / followed line / open
  stop) and stays quiet otherwise; Nearby jam row + follow-ahead warning (direction
  + along-track "ahead" gated); cascading KV thresholds (`config:jam_t_*`,
  `config:jam_downstream_horizon_s` = downstream banner reach by travel time, not a
  fixed count). Staging **`jam:sim`** KV / `?sim=<line>` injects a synthetic jam to
  verify without a live one. Design doc: `docs/JAM_DETECTION.md`. Report
  `docs/reports/2026-07-20-jam-detection.md`. **Open tails** (now separate chips in
  Next): calibrate the preliminary thresholds on the first live jam → then decide on
  `jam_detection_show` prod enable; watch `vehicle_fixes` D1 write volume;
  schedule-deviation (7a) + headway-CV (7d) already handed to the citywide branch.

- 🚧 **Adaptive context panel** (`feature/context-panel`, isolated preview pair,
  merge owner-gated) — the nearby / stop / vehicle bottom sheets become one
  **context slot** with three views and back navigation (nearby → stop →
  vehicle), driven by the state machine already in main. Desktop (≥840px) = a
  persistent left panel (rubber-band 360/28%/440) + full-height map with a
  persistent global search; mobile = the same content as unified bottom sheets
  (peek/half/large). The followed vehicle is kept in the visible map area
  (camera padding follows the panel width / sheet detent — the visible-track
  contract); a **follow-lost** pill ("Back to vehicle", l10n triple) shows on a
  manual pan or when the vehicle leaves the screen. Flag `context_panel` (OFF
  prod / ON staging) is the killswitch = today's independent sheets. Content
  extracted to reusable widgets (`StopBoard`, `NearbyView`, `VehicleView`) — no
  duplication; progresses the shared-stop-board item below. One declared
  divergence from the mock: the vehicle view's per-stop ETA list stays on the
  map, not the panel. Report `docs/reports/2026-07-18-context-panel.md`. Open
  follow-ups (separate tasks): route My Stops rows into the desktop panel-stop
  view; per-stop ETAs in the panel vehicle view.

- 🚧 **UX batch** (`feature/ux-batch-0720`, merged to main + prod 2026-07-21) —
  built on the context panel: desktop panel now **collapses** (Google-Maps
  "islands": search + burger float as separate backdrops, the map reclaims the
  space); all mobile bottom sheets **unified to full width** + shared
  handle/detents, "About the vehicle" opens **in-place** with a back arrow, and
  the map shifts up so the stop stays above the sheet; **global search
  everywhere** (nearby matches first, then stops/lines; works without a location
  fix). New **drawer "about & contact" footer**: in-app feedback form →
  `POST /api/v1/feedback` (durable D1 `feedback` table + best-effort GitHub issue
  to the private `stigla-feedback` repo), open-source licenses (AGPL-3.0), in-app
  privacy policy (EN/RU/SR **draft — owner proofread pending**), donate behind
  `config:donate_url`, dimmed version line. Panel/search/sheets shipped ON; the
  **feedback form stays behind `feedback_form` (OFF prod)** until the owner
  reviews the privacy text + enables it. Report
  `docs/reports/2026-07-20-ux-batch.md`.
  - **Follow-up shipped to the branch** (`feature/drawer-donate-footer`,
    isolated preview pair, merge owner-gated): the creator banner is reoriented
    to **donations** (opens `config:donate_url`, shown only when set); feedback
    becomes a **"Share feedback"** list item; the standalone Donate item is
    removed; About is trimmed to the unofficial disclaimer; the privacy DRAFT
    marker is dropped (wording approved); `.github/FUNDING.yml` added. Prod
    go-live (owner, after preview accept): set `config:donate_url` + enable
    `feedback_form`. Report `docs/reports/2026-07-24-drawer-donate-footer.md`.

- 🚧 **Transport on the map — a map toggle** (`feature/vehicle-mode-setting`,
  isolated preview pair, merge owner-gated) — on-demand becomes the **new
  default**, not an experiment. The single control is a **quick toggle on the map**
  (layers button in the right control stack, tap → switch + a toast naming the
  mode; owner picked it from two gallery concepts) — deliberately **no Settings
  item**. The choice persists locally and applies on the fly, no restart.
  `vehicles_on_demand` changes meaning — from a rollout switch to a **permanent
  two-level gate**: OFF hides the toggle and forces the aquarium (the killswitch,
  = today's prod), ON offers the choice with on-demand as the default; the
  resolution is `app/lib/core/vehicle_map_mode.dart`, registry updated. Also
  pushes the aquarium's `/vehicles/nearby` fan-out — the path that blows the
  Cloudflare subrequest limit on a cold cache — into opt-in. Same branch, by owner
  decision: **Ideas hidden** from the drawer (`kIdeasNavVisible`, code kept) and
  the language list is **Serbian-first**. Report
  `docs/reports/2026-07-17-vehicle-mode-setting.md`.

- 🚧 **Arrivals dedup — live/scheduled + scheduled roll-up** (`feature/arrivals-dedup`,
  staging preview, merge owner-gated) — with the schedule fallback ON the stop
  shutter double-counted: live boards and Scheduled rows of the same line
  duplicated each other. Now the list is grouped by **line×direction**; while a
  group has live vehicles, its non-live rows (Expected *and* Scheduled) at/under
  the latest live ETA are suppressed (same physical vehicles), and the surviving
  Scheduled collapse into **one** dimmed “<line> · Scheduled” cell (nearest +
  two, max three). Suppression stacks a **global** horizon (any non-live entry
  below the board's soonest live ETA is a phantom — hidden, any line; no live →
  nothing suppressed) on the per-line one. The list is then two **global**
  sections — **all** live rows (by ETA) then **all** non-live (Expected rows +
  Scheduled cells by nearest) — so no scheduled/expected ever sits above any
  live. Far ETAs (≥ 90 min) render as a 24h clock arrival time, not an
  unreadable minute count. Expected keeps its own per-vehicle row; live rows /
  comfort sort / per-line filter untouched. Applied on the **in-app** shutter
  (`stop_sheet.dart`) and mirrored in `StopScreen`; the **Nearby** card shows a
  line's live times only when it has live (no scheduled tail), and live cards
  sort above schedule-only cards. Pure
  `groupArrivals` / `visibleNearbyEtas` / `orderNearbyGroups` (unit-tested) + a cell widget;
  client-only, backend untouched. Visually verified on the preview (Batutova).
  Contract in git (`SCHEDULE_FALLBACK_CONTRACT.md`). Report:
  `docs/reports/2026-07-16-arrivals-dedup.md`.

- 🚧 **Marker motion — two mergeable layers** (`feature/stop-dwell-animation`,
  isolated preview pair, merge owner-gated, **merge in two parts** so each
  layer's prod effect is separately revertable).

  **Part 1 — the catch-up loop** (`fix(app): markers saw, freeze mid-block, and
  shove each other apart`). A **production** bug, valuable on its own and
  independent of the dwell. `_epsilonMeters` (0.5 m) was used as if the marker's
  distance from its target measured motion. It doesn't: `target` is read at the
  end of the step, so a marker tracking perfectly sits one frame behind it —
  gap settles at planVel·dt (~22 mm at 60 fps). Two consequences, one root:
  (a) within the epsilon the loop commanded a **dead stop**, so it braked every
  frame → a limit cycle, gap pinned at 0.5 m, speed sawing ~0..2× the plan, and
  on a slow segment every trough hits zero — **this is what "markers freeze
  mid-block" always was**, not a data desync; (b) `hasForwardMotion` tested the
  same gap, so a moving vehicle reported **stationary on every frame** (0/2101
  measured) and the spiderfy gate fanned it apart. `c5f4547` built pass-through
  spiderfy on that predicate meaning "the plan still has time to run";
  `8dab5e9` re-pointed it at the instantaneous gap a day later. One predicate,
  two meanings; the limit cycle then flickered it true often enough to keep the
  ticker alive and the fan shoving. Fixing the loop alone would have pinned the
  gap at 22 mm and frozen the whole map — the two are one change. Measured by
  replaying a **real** line-5 plan on its real GTFS shape at 60 fps:
  0.00–4.68 m/s and 89 near-zero frames → 1.289–1.289, gap 0.000, 2101/2101
  "moving".

  **Part 2 — the stop dwell** (`feat(app): pause at stops, …`). Pure realism now
  that the buffer role is gone: the marker brakes into a stop, stands ~3 s and
  pulls away. Plan waypoints already **are** the stops (verified against GTFS:
  waypoints 1..20 sit at 0.0 m from their pins) and their ETAs already price in
  dwelling, so the time is redistributed, not invented — waypoint position *and*
  time stay exact, only the curve between them is reshaped, so total plan time
  cannot drift by construction. Honesty contract untouched; backend untouched;
  no flag. Degrades to the old glide where a pause can't be plausible (accel
  ≤2.5 m/s², cruise ≤60 km/h, and no braking into a stop the next segment leaves
  at speed — all three still measured to earn their place; a dwell-fraction cap
  didn't and was dropped). Also completes the spiderfy contract: a **dwelling**
  vehicle is not fanned either (it's stillness that resolves itself in 3 s), and
  the fan's overlap threshold is now hysteretic (form at 24 px, collapse at
  40 px). Report: `docs/reports/2026-07-17-stop-dwell-animation.md`.

- ⏭️ **Elastic stop dwell (desync buffer)** — *withdrawn; do not start.* Idea was
  to stretch a pause at a stop when the board nears the 45 s gate. Two things
  killed it: the freeze it was meant to buffer turned out to be the catch-up
  limit cycle above, not data; and the read-out that would set its threshold says
  there is nothing to buffer — only a board landing older than **15 s** dooms a
  marker to freeze, and boards land **0–3 s** old (owner's own capture:
  `freeze-bound 0/1`). Reopen only with samples taken *while a freeze is actually
  observed*. (Caution: the first read-out was itself wrong — counting the
  provider's re-emitted previous board reported 263 s of fake staleness; fixed.
  Backgrounded tabs also pause polling.)

- ✅ **Analytics insert hardening** (`fix/analytics-sql-variables`, merged to `main`
  2026-07-16) — the analytics-D1 insert chunk size is derived from the column count
  to stay under D1's documented limit (100 bind parameters), via one helper for all
  paths (observations + aggregates). Prod check: **there was no silent data loss**
  (the binding limit is above the REST limit, so the chunk of 40 actually held).
  Report: `docs/reports/2026-07-15-analytics-sql-variables.md`.

- ✅ **Product analytics contour** (`feature/product-analytics`) — our own contour
  for product events: a client `EventLogger` (queue + batch-flush + ephemeral
  in-memory session, no user-id/IP/coordinates) posts batches to
  `POST /api/v1/events`, and the worker writes them to a new `product_events` table
  (analytics-D1) via `chunkedInsert` in `waitUntil` — zero impact on the hot paths.
  8 v1 events (incl. `app_open.locale_class` for local/tourist cohorts), properties
  as enums only (unknown events/properties are dropped at the door). The
  `product_analytics` gate (OFF prod / ON staging) closes **both** ends: with it OFF
  the client sends zero requests. A privacy paragraph was added to the README. Prod
  is a separate decision after checking volumes. Report:
  `docs/reports/2026-07-18-product-analytics.md`.

- 🚧 **Line analytics screens** (heatmap / sparkline / scatter / stat tiles) —
  hidden on production, visible on staging; draft visuals.
- 🚧 **Coverage tab (V0)** — a standalone Strava-style route-density infographic
  (filter by vehicle type, gradient legend), hidden on production for now.

## Next

### Jam detection & citywide analytics — open tails (post-merge 2026-07-20)
- ⏭️ **Calibrate the jam thresholds on the first live jam**, then decide on the
  `jam_detection_show` prod enable. `T_jam` is preliminary (cascade 300/180/90s,
  KV `config:jam_t_*`) — validated only as "does not fire on feed starvation", never
  against a real jam's magnitude. Recalibrate on the first captured live jam; the
  prod enable of the UI flag is gated on that calibration.
- 🟡 **Prod aggregate backfill — windowed rewrite done, primary metric correct,
  secondary passes blocked on CPU budget** (branch `fix/aggregate-windowed-backfill`,
  NOT merged). Full story: `docs/reports/2026-07-21-aggregate-windowed-backfill.md`
  (and the original failure `docs/reports/2026-07-21-prod-backfill-verify.md`).
  - The one-shot full backfill was replaced by a **windowed** aggregate: each run
    processes ≤ `config:agg_backfill_window_s` (KV, default 1 day) and advances
    `last_run` **atomically with the bucket writes in one `db.batch()`** (found &
    fixed a double-count where a CPU-limit kill between separate bucket/watermark
    writes inflated samples to 2.5×). `aggregateVehicles`/`sched_delay` are
    best-effort after the atomic commit. sched_delay match made O(1)-per-arrival
    via memoisation (hub stop 21577 had 3789 arrivals on the 07-17 outage day).
    172/172 backend tests green (convergence + idempotency + config-window).
  - **Prod state:** primary metric correct & converged to 07-20 18:28
    (`SUM(samples)==COUNT(raw)=401,273`, no double-count); ~17h window left;
    `agg_vehicle_line`=1478; **`sched_delay_count`=0**. No user impact
    (`analytics_show` OFF).
  - **Open blocker:** the full `aggregate()` (all passes) does NOT fit the admin
    **fetch-path** CPU budget at these volumes — it dies in the secondary passes
    after the atomic commit, so sched_delay stays 0 (over-forcing ~60 admin calls
    also exhausted the fetch CPU budget: heavy call → 503/1102, light paths 200).
  - **Next:** confirm at the 06:00 UTC **cron** (bigger budget) whether a clean
    1-day-window run completes (log `caughtUp` + `sched_delay_count>0`); if not,
    **split aggregate** — primary in cron, heavy vehicles/sched in a separate
    deferred pass / smaller windows. Backfill the historical sched_delay gap
    off-peak afterwards. Chip stays OPEN.
- ⏭️ **Monitor D1 write volume against the free tier.** Three writers now feed D1:
  `vehicle_fixes` upsert on every fresh board (jam), the sweep (~27k rows/day), and
  organic (~41k/day) → ~68k/day writes, 32% headroom under the 100k/day free tier.
  Watch the sum; killswitches are `jam_detection_collect` and `analytics_sweep`
  (both single KV writes, no redeploy; the sweep also has the auto circuit-breaker).
- ⏭️ **Raise the sweep tempo to 11s** (~early August, only if no challenge signs) —
  KV `config:sweep_interval_day_seconds`, raised in steps, never hardcoded. The
  only knob facing the source; start 20s, target 11s.
- ⏭️ **Feed↔GTFS line-label mapping.** `sched_delay` surfaced a desync: 18.3% of
  arrivals have no GTFS timetable at their stop, largely live-vs-GTFS label
  mismatches (e.g. stop 21577 — the feed labels line 55, GTFS lists only 309 there).
  A separate reconciliation/dictionary task; the unmatched fraction is itself a
  data-quality signal, not a matcher bug (only 0.1% had a timetable but no trip).
- ⏭️ **incident_journal / feed_hunger** — the deferred **phase 2** of the v2
  migration (wiring the jam incident journal into analytics + a citywide
  freeze-frequency map). Lands with a later jam↔analytics stitch.
- ⏭️ **Surface punctuality (`sched_delay`) on the analytics screens** — the data is
  accruing but the API returns null (`punctuality`); a later screen task once
  1–2 weeks of citywide history exists.
- 🧊 **Owner dashboard** — a flag-gated network overview for the owner (network
  now, sweep health, weekly trends, incident log). Principle: **the flag is a
  shutter, not a lock** — anything sensitive goes only through authenticated
  endpoints, never merely hidden behind a client flag.

### Data freshness & suburban coverage
- ✅ Verified the city GTFS feed is already the latest official export (a rebuild
  is byte-identical) — missing lines were structurally in a *different* dataset
  (suburban), now handled.
- 🧊 **Retiring GTFS "ghost" lines** — deferred until enough history accumulates
  (~4–8 weeks). Measurement showed the real residue is tiny (most "unseen" lines
  are night lines that simply don't run at night). A month+ of data makes
  night/rare lines distinguishable from retired ones; build the classifier then.
- 🎯 **Rendering on a starved source feed (priority: AFTER product-analytics).**
  Measured 2026-07-18 (fixAge instrumentation + prod-vs-staging identity): the
  upstream routinely falls into **minute-long GPS-update pauses**. Caught **three
  windows over two days**: 07-17 evening 11/11 vehicles fixAge>45s; 07-18 daytime
  baseline **20-26%**; 07-18 evening 11/12. Yet the prod feed is fresh by `as_of` —
  **HOLD ≈0% on prod** (day AND evening, 5-min sample): the starvation shows up not
  as HOLD but as a **re-stamp** (the upstream advances `as_of`, not the GPS) —
  ~20-21% of vehicles are predicted from a frozen fix, freeze p90 ≈**91s**. Of the
  frozen fixes, **~26-33% are legitimate terminals/layovers** (a real stop, not the
  feed's fault); the rest is source under-supply.
  - The phenomenon renders differently by cache warmth: on prod (warm `as_of`) —
    **re-stamp jumps** (the marker jumps when a fresh fix finally arrives); on a
    cold staging stand the same starvation is a **chorus HOLD** (all vehicles stall
    in sync). Feed identity proven: 51/52 shared `garage_no` have identical GPS
    (prod and staging are one feed, different SWR caches). See memory
    `staging-stand-cold-cache-hold`.
  - Two candidates for a soft degradation (elastic rendering): (1) instead of a
    re-stamp jump — slow down / flag the uncertainty; (2) on a mass HOLD — a single
    map "data is delayed" indicator instead of N pale markers.
  - The related **spiderfy episode** (fanning out stationary vehicles on a chorus
    HOLD snapped instantly) is already fixed with an ease (`8404af9`) — but it
    highlighted that a starved feed also breeds visual artifacts.
  - For a future **API outreach**: "your feed routinely falls into minute-long
    (p90≈91s) GPS-update pauses." Priority — after product-analytics (we need the
    window-frequency numbers from analytics to decide the scale of the
    degradation).

### Known cosmetics (not blockers)
- 🧊 **Semi-transparent "ghost" marker next to a stationary vehicle (follow).**
  Observation conditions (owner, R5): on-demand, following **7L P80236** from stop
  **20094**'s context, the vehicle paused — a semi-transparent marker of the same
  kind appears beside it. Rare, semi-transparent. A code audit (R5) ruled out:
  double-track (in on-demand garageNo is unique), an aquarium twin (aquarium off),
  a double render path (the vector symbol layer is the only one on the main map;
  `VehicleMarker` lives only in `live_vehicles_map`), un-smoothed stale (the source
  is overwritten wholesale). On the main map the pipeline yields one track → one
  feature. What remains is a rare render artifact (candidates: a residual spiderfy
  offset on the dwell↔move transition; a grace-fade at the vehicle itself on a
  re-anchor frame). Needs a live repro with layer inspection. Does not block the
  stop-dwell branch merge.

### Plumbing / reliability
- ⏭️ **Суточная/историческая агрегация upstream req/hr (наблюдаемость бюджета).**
  `upstream_events` (метр `upstream_budget`) имеет retention ~2ч (opportunistic
  prune в sweep-тике), а `/admin/sweep/status` отдаёт только rolling-1h — как
  только `analytics_sweep` включён (сделано 2026-07-23), суточную картину req/hr
  из D1 уже не снять. Нужен лёгкий дневной rollup req/hr по часам (или подъём
  retention) — чтобы выставлять/пересматривать бюджет C по реальному пику без
  ручного окна «пока sweep был выключен». Не блокер; подробности —
  `docs/reports/2026-07-23-sweep-enable.md` §7.
- ⏭️ **The GTFS shape doesn't cover the central stretch of lines 26/27/44 (and
  probably others) — it breaks track rendering, not just the pauses.** Measured on
  live vehicles (R5, 2026-07-18): the raw `all_stations` are real GTFS stops
  (`id∈GTFS`, 0 m coordinates), but the direction polyline runs past the block of
  real stops by **77–721 m** (line 26: 7 of 23 stops off-shape; line 27: 4 of 26).
  Projecting such a stop onto the polyline drops both the marker and its pause
  hundreds of meters away, onto a neighbouring street (the user sees a "pause at an
  oncoming pin / between stops"). Lines 79/31/29/EKO2 have a fine shape — the bug
  is on a subset. **City-wide extent unknown:** an honest measurement requires
  checking the shape against the ACTUAL trip stations (live vehicles per direction)
  — a quick measurement against the self-consistent `stops` endpoint is
  tautological (0 m) and won't do; it's part of the geometry-fix task.
  The direction (`resolveDirectionRouteId`) is CORRECT here (the destination
  terminal matches) — it's not the resolve, it's the shape geometry (a route
  variant / a different routing in GTFS). Fix: rebuild/pick a shape that matches the
  actual route; until then, on these lines pauses are gated by proximity to a real
  stop (see the stop-dwell branch), so there are fewer pauses, and that's honest.
  **Sub-case — one shape per route with no directions.** Some GTFS routes have a
  single polyline (no per-direction `-0`/`-1` variants), so there's nothing to pick
  "the same direction as the vehicle" from (the follow fix from the stop-dwell
  branch) — both sides project onto one line, and the highlight/pauses land on the
  wrong side. For such routes, draw the track **by the vehicle's actual movement**
  (the sequence of its GPS fixes / `all_stations`), not by a fixed direction
  polyline. Part of the general geometry-fix task.
  **~8% of feed lines have no shape at all (suburban / ADA operators, not in our
  474 GTFS lines — e.g. "Ada 4" at Batutova).** For following such a vehicle a
  **raw mode** is implemented (branch `feature/context-panel`, R4): no route line,
  the marker on pure GPS (`VehicleTrackAnimator.dropTimed`, re-set after each
  re-sync of the stop context so the vehicle doesn't "drive through buildings"),
  the panel shows "Route unavailable for this line" (l10n triple). The degradation
  is honest, it lies about nothing. As GTFS coverage grows (these lines appear in
  the feed with a shape) — revisit: the raw mode should automatically give way to
  the normal track. Same cluster as 26/27/44.
- ⏭️ **A single gateway to the source (egress discipline, full layer)** — funnel
  all upstream traffic from all environments (prod + every isolated staging
  version) through one piece of code with **one global rate limit**, single-flight
  and a short shared cache, so that N stands cost the source like ~1 poller (today
  each isolate polls independently, and the 30s cap only holds inside an isolate).
  Motive: the source appears to run behavioural TTL classification — on 2026-07-17
  it served our Cloudflare egress HTML instead of JSON for hours, then let go on its
  own; quieter = less risk of a repeat. Predecessor layers: the diagnostic rule in
  CLAUDE.md (done), a provider-level rate ceiling (in the next backend task). Full
  plan and traffic discipline: `docs/reports/2026-07-17-upstream-egress-outage.md`.
- ✅ **Scheduled map objects TypeError** (merged to `main` 2026-07-16) —
  `scheduledMapObjectsForRoute` threw on the edge input
  `now.minutes === last stop time`, and one bad route dropped the *whole*
  scheduled layer of a `/vehicles/nearby` response (silent). Root fix + per-route
  isolation on `fix/scheduled-map-typeerror`. Report:
  `docs/reports/2026-07-16-scheduled-map-typeerror.md`.
- 🚧 **Cold `/vehicles/nearby` subrequest budget** — worst-case cold path was
  ≈70–73 subrequests, over the 50/invocation tier. Done on the branch above:
  per-invocation memo of `getFlag("analytics_collect")` (18 per-stop KV reads →
  1, cold worst-case ~70 → ~53). Still over on a fully cold isolate; the larger,
  architectural levers (fan-out reduction, upstream cache policy) are deferred.
  Full decomposition in the report above.
- ⏭️ **Unify the two stop-shutter render paths** — `stop_sheet.dart` (in-app tap,
  primary) and `stop_screen.dart` (`/stop/:id` deep link) each carry their own
  copy of the arrivals-list build (freshness, line filter, comfort sort, grouped
  entries). The duplication already misfired in `arrivals-dedup` (the dedup
  landed in `stop_screen` first and did nothing in the app until wired into
  `stop_sheet` too). Extract one shared arrivals-list widget both consume, so a
  future list change can't ship a half-fix. Client-only refactor, no behaviour
  change; lock it with the existing widget tests. **Partly done** on
  `feature/context-panel`: the sheet's board is now the shared `StopBoard`
  widget (also hosted by the desktop panel); `stop_screen.dart` (deep link) is
  the remaining copy to fold into `StopBoard`.

### Fleet-ID tail
- ⏭️ Close remaining roster gaps so fewer vehicles show as UNKNOWN.
- ⏭️ Quarterly roster-refresh pipeline — use first/last-seen from accumulated
  history to auto-detect retirements and new deliveries.
- Interior-diagram hero for the model card (see "vehicle models" below).

## Ideas

- 💡 **Reliability in the main UI** (needs ~4–8 weeks of history): a line
  reliability badge, an honest ETA range when spread is high, "best/worst time
  to ride" on the line card.
- 💡 **Punctuality vs the GTFS schedule** — needs trip matching; unblocks the
  reliability metrics above.
- 💡 **Expected conversion (diagnostics).** From analytics (observations since
  2026-07-10), compute what fraction of placeholder predictions (garage `P1..P999`)
  converts into a real live vehicle, broken down by ETA range (0–5 / 5–15 / 15+ min)
  and time of day (day/night). Goal: use data to confirm or refute trust in the
  **Expected** status at small ETAs; if the conversion at ETA < N min is near zero —
  justify a hide rule. A candidate for the first reliability-pillar case (showing
  prediction reliability to the user). A purely analytical task, doesn't touch the
  product. Context: the owner's question 2026-07-17, "7 minutes Expected — it looks
  like it's not coming anymore."
- 💡 **Dropped-trips metric** — computable from current data.
- 💡 **Coverage V2** — weight segments by time-of-day/day-of-week aggregates,
  with a "how it usually is at this hour" slider (after enough history).
- 💡 **Vehicle models, step 1 — interior diagrams** (AI-assisted): reference
  class first, then the top classes by fleet size, integrated into the model
  card.
- 💡 **`maplibre` plugin upgrade** to drop two web workarounds and get clean
  multi-map rendering (needs a full map-surface regression).

## Later

- 💡 **Vehicle models, step 2 — a "spin around" view** (sprite frames or
  lightweight 3D), top classes only, gated on step-1 engagement.
- 💡 **Crowdsourcing** — reports attached to a *vehicle*, not a line (e.g. "A/C
  broken" on a specific vehicle follows it across future trips), enabled once
  there's a live audience.
- 💡 Open the analytics screens to users once the visuals are polished.

## Icebox (intentionally not doing; revisit condition in parentheses)

- 🧊 Journey planning: A→B routing, transfers, walking legs, weather modifiers
  (if the concept expands).
- 🧊 Real-time crowding (no sensors; revisit at audience scale).
- 🧊 Neighborhood/time safety (ethically fraught).
- 🧊 Fares (Belgrade is free; at most a tourist FAQ page).
