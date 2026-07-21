# Stigla — Roadmap

Where the product is and where it's going. Status: ✅ shipped · 🚧 in progress /
behind a flag · ⏭️ next · 💡 idea · 🧊 icebox.

## Product frame

Stigla is **not a journey planner** (no A→B routing). It answers the two
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

- ✅ **Analytics insert hardening** (`fix/analytics-sql-variables`, влито в `main`
  2026-07-16) — размер чанка вставки в analytics-D1 выводится из числа колонок под
  документированный лимит D1 (100 bind-параметров), одной утилитой для всех путей
  (наблюдения + агрегаты). Проверка прода: **тихой потери данных не было**
  (binding-лимит выше REST-лимита, чанк 40 фактически держал). Отчёт:
  `docs/reports/2026-07-15-analytics-sql-variables.md`.

- ✅ **Product analytics contour** (`feature/product-analytics`) — собственный
  контур продуктовых событий: клиентский `EventLogger` (очередь + батч-flush +
  эфемерная in-memory session, без user-id/IP/координат) шлёт батчи на
  `POST /api/v1/events`, воркер пишет в новую таблицу `product_events`
  (analytics-D1) через `chunkedInsert` в `waitUntil` — ноль влияния на горячие
  пути. 8 событий v1 (вкл. `app_open.locale_class` для когорт местные/туристы),
  свойства только перечислениями (unknown события/свойства отбрасываются на
  входе). Гейт `product_analytics` (OFF прод / ON staging) закрывает **оба** конца:
  при OFF клиент шлёт ноль запросов. README-абзац о приватности добавлен. Прод —
  отдельным решением после проверки объёмов. Отчёт:
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
- 🎯 **Подача на голодном фиде источника (приоритет: ПОСЛЕ product-analytics).**
  Замер 2026-07-18 (fixAge-инструментация + прод-vs-staging тождество): upstream
  штатно проваливается в **минутные паузы обновления GPS**. Поймано **три окна за
  два дня**: 07-17 веч 11/11 бортов fixAge>45с; 07-18 день база **20-26%**;
  07-18 веч 11/12. При этом прод-фид по `as_of` свеж — **HOLD ≈0% на проде**
  (день И вечер, 5-мин сэмпл): голод виден не как HOLD, а как **re-stamp**
  (upstream двигает `as_of`, не GPS) — ~20-21% бортов предсказывают по
  замороженному фиксу, p90 заморозки ≈**91с**. Из frozen-фиксов **~26-33% —
  легитимные терминалы/стоянки** (реальный стоп, не вина фида); остальное —
  недоподача источника.
  - Феномен рендерится по-разному по тёплости кэша: на проде (тёплый `as_of`) —
    **re-stamp-прыжки** (маркер прыгает, когда свежий фикс наконец приходит); на
    холодном staging-стенде тот же голод — **хоровой HOLD** (все борта встают
    синхронно). Тождество фида доказано: 51/52 общих `garage_no` — GPS идентичны
    (прод и staging — один фид, разные SWR-кэши). См. memory
    `staging-stand-cold-cache-hold`.
  - Два кандидата на мягкую деградацию (эластичная подача): (1) вместо
    re-stamp-прыжка — замедлять/помечать неуверенность; (2) при массовом HOLD —
    общий индикатор карты «данные задерживаются» вместо N бледных меток.
  - Связанный **spiderfy-эпизод** (развод стоящих на хоровом HOLD снапал
    мгновенно) уже пофикшен ease'ом (`8404af9`) — но подсветил, что голодный фид
    рождает и визуальные артефакты.
  - Для будущего **API-outreach**: «ваш фид штатно проваливается в минутные
    (p90≈91с) паузы обновления GPS». Приоритет — после product-analytics (нужны
    цифры частоты окон из аналитики, чтобы решать масштаб деградации).

### Known cosmetics (not blockers)
- 🧊 **Полупрозрачный «призрак»-метка рядом со стоящим бортом (follow).** Условия
  наблюдения (владелец, R5): on-demand, follow за **7L P80236** из контекста
  остановки **20094**, борт на паузе — рядом появляется полупрозрачная метка того
  же вида. Редкий, полупрозрачный. Кодовый поиск (R5) исключил: дубль-трек
  (в on-demand garageNo уникален), твин-из-аквариума (аквариум off), двойной путь
  рендера (векторный symbol-слой — единственный на главной карте; `VehicleMarker`
  живёт только в `live_vehicles_map`), несглаженный stale (source
  перезаписывается целиком). На главной карте пайплайн даёт один трек → одну фичу.
  Остаётся редкий рендер-артефакт (кандидаты: остаточный spiderfy-offset при
  переходе dwell↔move; grace-fade у самого борта на кадре ре-анкора). Нужна живая
  репродукция с инспекцией слоя. Не блокирует merge ветки stop-dwell.

### Plumbing / reliability
- ⏭️ **GTFS shape не покрывает центральный участок линий 26/27/44 (и, вероятно,
  др.) — ломает отрисовку трека, не только паузы.** Замер на живых бортах
  (R5, 2026-07-18): сырые `all_stations` — настоящие GTFS-стопы (`id∈GTFS`,
  координаты 0 м), но полилиния направления идёт мимо блока реальных стопов на
  **77–721 м** (line 26: 7 из 23 стопов off-shape; line 27: 4 из 26). Проекция
  такого стопа на полилинию садит и метку, и её паузу за сотни метров, на
  соседнюю улицу (пользователь видит «паузу у встречного пина / между
  остановками»). У линий 79/31/29/EKO2 shape в порядке — баг на подмножестве.
  **Городской охват неизвестен:** честный замер требует сверки shape с
  ФАКТИЧЕСКИМИ станциями рейсов (живые борта по каждому направлению) — быстрый
  замер по self-consistent `stops` эндпоинта тавтологичен (0 м) и не годится;
  входит в задачу фикса геометрии.
  Направление (`resolveDirectionRouteId`) при этом ВЕРНОЕ (destination-терминал
  совпадает) — дело не в резолве, а в геометрии shape (вариант маршрута / иная
  прокладка в GTFS). Фикс: пересборка/выбор shape, совпадающего с фактическим
  маршрутом; до него — на этих линиях паузы гейтятся близостью к реальному стопу
  (см. ветку stop-dwell), поэтому пауз меньше, и это честно.
  **Подслучай — один shape на маршрут без направлений.** Часть маршрутов в GTFS
  имеет единственную полилинию (нет per-direction вариантов `-0`/`-1`), поэтому
  выбирать «то же направление, что у борта» (фикс follow из ветки stop-dwell)
  не из чего — обе стороны проецируются на одну линию, и подсветка/паузы садятся
  не на ту сторону. Для таких маршрутов рисовать трек **по факту движения** борта
  (последовательность его GPS-фиксов / `all_stations`), а не по фиксированной
  полилинии направления. Часть общей задачи фикса геометрии.
  **~8% линий фида вообще без shape (пригородные / АДА-перевозчики, не входят в
  наши 474 GTFS-линии — напр. «Ada 4» с Batutova).** Для follow по такому борту
  реализован **сырой режим** (ветка `feature/context-panel`, R4): без линии
  маршрута, метка по чистому GPS (`VehicleTrackAnimator.dropTimed`,
  переустанавливается после каждой ре-синхронизации стоп-контекста, чтобы борт не
  «поехал сквозь дома»), панель показывает "Route unavailable for this line"
  (l10n-триада). Деградация честная, ничего не врёт. При росте покрытия GTFS
  (эти линии появятся в фиде с shape) — пересмотреть: сырой режим должен
  автоматически уступить место обычному треку. Тот же кластер, что 26/27/44.
- ⏭️ **Единый шлюз к источнику (egress discipline, полный слой)** — свести весь
  upstream-трафик всех окружений (прод + все изолированные staging-версии) в один
  код с **одним глобальным рейт-лимитом**, single-flight и коротким общим кешем,
  чтобы N стендов стоили источнику как ~1 поллер (сейчас каждый изолят поллит
  независимо, 30с-кап держится только внутри изолята). Мотив: источник, похоже,
  ведёт поведенческую TTL-классификацию — 2026-07-17 он на часы отдавал нашему
  Cloudflare-egress HTML вместо JSON, потом сам отпустил; тише = меньше риск
  повтора. Слои-предшественники: правило диагностики в CLAUDE.md (готово),
  провайдерский потолок частоты (в ближайшей бэкенд-задаче). Полный план и
  дисциплина трафика: `docs/reports/2026-07-17-upstream-egress-outage.md`.
- ✅ **Scheduled map objects TypeError** (влито в `main` 2026-07-16) —
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
- 💡 **Expected-конверсия (диагностика).** По аналитике (наблюдения с
  2026-07-10) посчитать, какая доля placeholder-прогнозов (гараж `P1..P999`)
  конвертируется в реальный live-борт, в разрезе диапазонов ETA (0–5 / 5–15 /
  15+ мин) и времени суток (день/ночь). Цель: данными подтвердить или
  опровергнуть доверие к статусу **Expected** при малых ETA; если конверсия при
  ETA < N мин близка к нулю — обосновать правило скрытия. Кандидат на первый
  кейс reliability-pillar (показ надёжности прогноза пользователю). Чисто
  аналитическая задача, продукт не трогает. Контекст: вопрос владельца
  2026-07-17 «7 минут Expected — выглядит так, будто уже не приедет».
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
