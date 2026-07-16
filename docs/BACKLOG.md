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

## In progress / behind a flag

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

- ✅ **Analytics insert hardening** (`fix/analytics-sql-variables`, влито в `main`
  2026-07-16) — размер чанка вставки в analytics-D1 выводится из числа колонок под
  документированный лимит D1 (100 bind-параметров), одной утилитой для всех путей
  (наблюдения + агрегаты). Проверка прода: **тихой потери данных не было**
  (binding-лимит выше REST-лимита, чанк 40 фактически держал). Отчёт:
  `docs/reports/2026-07-15-analytics-sql-variables.md`.

- 🚧 **Line analytics screens** (heatmap / sparkline / scatter / stat tiles) —
  hidden on production, visible on staging; draft visuals.
- 🚧 **Coverage tab (V0)** — a standalone Strava-style route-density infographic
  (filter by vehicle type, gradient legend), hidden on production for now.

## Next

### Data freshness & suburban coverage
- ✅ Verified the city GTFS feed is already the latest official export (a rebuild
  is byte-identical) — missing lines were structurally in a *different* dataset
  (suburban), now handled.
- 🧊 **Retiring GTFS "ghost" lines** — deferred until enough history accumulates
  (~4–8 weeks). Measurement showed the real residue is tiny (most "unseen" lines
  are night lines that simply don't run at night). A month+ of data makes
  night/rare lines distinguishable from retired ones; build the classifier then.

### Plumbing / reliability
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
