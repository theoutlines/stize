# Contract: live + scheduled hybrid (scheduled objects)

A coordination document between the **symbol-layer** session (frontend: rendering
and motion) and the **gtfs-freshness** session (backend: scheduled
arrivals/objects). The frontend is already implemented against this contract
**tolerant + behind a flag** — the backend must emit fields with these names.
Flag: `schedule_fallback` (OFF prod).

## Idea

A scheduled object is **the same moving object**, not a new mechanism: the same
`MovingObjectKind` (bus/tram/…), the same motion format (a timed plan over
geometry), differing only in **source** (`source`) and render **opacity**. The
client drives it with **the same code** as a live one (timed extrapolation).

## `/api/v1/vehicles/nearby` — `VehicleDto` (map)

Additive fields on top of the existing live contract (all optional, an old client
doesn't break):

| field | type | for live | for scheduled |
|---|---|---|---|
| `source` | `"live" \| "scheduled"` | `"live"` or absent | `"scheduled"` |
| `trip_id` | `string?` | opt. (see dedup) | GTFS `trip_id` — trip identity |
| `line`, `vehicle_type`, `lat`, `lon`, `heading` | as now | — | position = "where the trip is now" = interpolation over the shape + scheduled times |
| `trajectory` | `TrajectoryPointDto[]` | as now | **the plan ahead from `stop_times`**, the same `{lat, lon, eta_seconds}` format |
| `as_of` | `string` (ISO) | as now | the moment the plan is anchored to |

**Key:** the `trajectory` for scheduled must be **the same format** as for live
(points over the route geometry + `eta_seconds` from `as_of`). Then the client
writes no new motion code — scheduled is driven by `TimedTrajectory` like live.
`eta_seconds` are cumulative seconds from `as_of` (0 at the current point,
monotonically ↑).

### Client (implemented)
- `source` is parsed tolerant: anything other than an explicit `"scheduled"` =
  `live` (`VehicleSource.fromApi`).
- The scheduled track key = `sched:<trip_id>` (or a coord fallback) — it **never
  collides** with a live key (the garage number).
- Rendering: scheduled is drawn at a base opacity of `0.5`
  (`kScheduledBaseOpacity`), combined with the grace/crossing fade; z-order —
  scheduled **below** live (a live one is always on top on overlap).
- Motion: a scheduled object's `trajectory`+`as_of` are fed to the animator
  **regardless** of the `timed_trajectory` flag (for a scheduled one the plan is
  its motion).
- A tap on scheduled → the same line shutter + an honest note "by schedule — not a
  live position" (`vehicleScheduled`, EN/RU/SR).

## Deduplication live vs scheduled (one trip)

- **Backend responsibility:** don't emit a scheduled object for a trip that has a
  live vehicle. The backend has a trip↔vehicle mapping; the client doesn't.
- **Client safety net (implemented):** the scheduled key is prefixed
  (`sched:`), so scheduled and live **can't occupy one track**. Full per-trip
  dedup is the backend's (if live starts carrying `trip_id`, the client can add
  dedup by it; live doesn't carry it today — to be agreed).

## Arrivals list (stop screen) — NOT in this session

Item 3 of the brief (a hybrid list: live bright/on-top, scheduled labeled, no empty
state if something is coming by schedule) **overlaps with the `gtfs-freshness`
session's work** on the stop screen (currently shows GTFS ∪ live,
`stop_screen.dart`) and "ghost" suppression. To avoid stepping on another session,
the list is built **coordinated there** (or by a separate owner replica), on this
same contract (`ArrivalDto.source`/`trip_id`). The symbol-layer session did the
**map** (render+motion) — its part.

Proposed `ArrivalDto` extension (for the list, when taken up):
`source?: "live" | "scheduled"`, `trip_id?: string` — the same names.

**Update (`arrivals-dedup`):** the client list-display rules are now fixed below —
the section "Arrivals list display rules (stop shutter)". The data
(`source`/`trip_id`) already arrives; the change is purely display-side, the
backend doesn't change.

## Flag

- `schedule_fallback` (KV, env-aware): OFF prod / ON staging by default.
- Client: with OFF scheduled objects are **dropped** before entering the animator
  (not drawn at all); with ON — drawn semi-transparent.
- The backend gates the **emission** of scheduled objects with the same (or its
  own) flag.
- Both must be ON for scheduled to run on staging.

## To confirm with the backend session (gtfs-freshness)
1. Field names: `source`, `trip_id` (snake_case) — ok?
2. Scheduled `trajectory` — points over the route's **road-shape** (like live
   `all_stations`), `eta_seconds` cumulative from `as_of`. Ok?
3. Trip dedup (live exists → don't emit scheduled) — does the backend take it on?
4. The emission flag — `schedule_fallback` or a separate one? (the client reads
   `schedule_fallback`.)

## Arrivals list display rules (stop shutter)

Introduced by the `arrivals-dedup` task. After the fallback was turned on (Phase 1)
the shutter became unreadable: live vehicles and Scheduled rows of the same line
**duplicate each other** ("it looks like there's too much transport, but they
actually just repeat each other" — the Batutova screenshot 2026-07-16: live 79
"2 min"/"14 min" mixed with five Scheduled 79 at 6/18/26/30 min). The point of the
fallback is to **fill emptiness, not to double live data**.

The rules are **purely client-side** (the backend doesn't change, the data already
arrives). Grouping — by **line × direction** (direction = `direction_route_id`, or
`route_id` when absent).

Three row statuses (`ArrivalRowStatus`, already in the code):
- **live** — a really tracked vehicle (GPS, garage); clickable, follow.
- **expected** — a valid ETA prediction **without** a live position (a placeholder
  vehicle, garage `P1..P999`, anchored to the stop). An honest "Expected", not a
  broken live.
- **scheduled** — the schedule fallback (`source=scheduled`), no vehicle at all.

### 1. Duplicate suppression — two overlaid horizons
A non-live row (Expected/Scheduled) is hidden if **either** fires:

- **Global horizon (across the whole stop).** If the stop has **at least one** live
  vehicle, any non-live row/cell of **any line** with an ETA **less than the nearest
  live-ETA vehicle** is a phantom (transport that "arrives sooner" than the visible
  live one would itself be visible as live) and is **hidden**.
  Boundary: `eta < min(live_eta over vehicles)` → hidden; exactly at the minimum —
  passes the global (the group decides next). Offender examples: Bregalnička "29
  Scheduled 1 min" against live 5/12/14; Pijaca Đeram "7L Scheduled Now".
- **Group horizon (line × direction).** On top of the global: non-live rows of the
  own group with an ETA **no later** than the latest live-ETA of **this line** — the
  same physical vehicles, hidden (`eta ≤ max(live_eta) of the group`).

**No live at the stop at all → suppress nothing** (the night case: the fallback
fills emptiness, as intended).

Example (Batutova): live 79 at 2 and 14 → Scheduled 79 at 6 hidden by the group; any
Scheduled of another line with ETA < 2 hidden by the global; 79 at 18/26/30 stay.

### 2. Collapsing Scheduled into one cell per group
The **Scheduled** remaining after (1) of one group render as **one** row
"<line> · Scheduled" with a clock icon. The time on the right — in two lines (the
"nearest + next" pattern, like Yandex):
- top line, large: the **nearest** Scheduled past the horizon;
- bottom line, smaller/dimmed: the next **two** times.

At most **three** times per cell, never more — the collapse gives "the whole
picture", not a full timetable. Fewer available (1–2 Scheduled) — we show as many as
there are.

**Expected is NOT collapsed.** Placeholder vehicles (`ArrivalRowStatus.expected`)
stay as **separate rows** labeled "Expected" — they have a valid ETA prediction of a
specific vehicle, it's not a timetable row. Collapsing only touches
`source=scheduled`.

### 3. Order in the list — **two global sections**, not by group
The list splits into two sections across the whole stop:
1. **Live section:** **all** live rows of all lines, sorted by ETA. Each vehicle a
   separate row (Fleet-ID, clickability, follow — untouched).
2. **Non-live section:** **all** remaining non-live — surviving **Expected** rows
   and collapsed **Scheduled** cells mixed together, sorted by nearest ETA.

**No scheduled/expected row ever sits above any live** — regardless of line and ETA.
"A scheduled one (even 'Now') won't arrive before someone already on the move."
Suppression (1) stays **per line × direction** — only the ordering is global. The
"By comfort" sort (a flat live-only mode) and the per-line filter — unchanged.

### 4. Semantics and rendering don't change
The "Scheduled" / "by schedule — not a live position" label stays; **"on schedule ≠
will arrive"**. No mimicry of live.

**Brightness = clickability** (the rule is already in the code, the collapse
inherits it):
- **live** — full brightness + chevron, clickable;
- **expected / scheduled** — dimmed, no chevron, non-clickable.

A collapsed Scheduled cell is rendered as `scheduled`: dimmed, non-clickable.

### 5. Nearby shutter — a card doesn't mix live and scheduled
A Nearby card is already grouped by line × direction (backend `NearbyGroup`,
`route_id` = `direction_route_id`/fallback). Rules (client-side, no backend):
- **Has live** → the card shows **only live times** (nearest + next live, if any);
  scheduled times **never make it in** (`2 min / 🕐 11 min` → `2 min` remains). A
  live time reads bright.
- **No live** → a scheduled-only card, as now: dimmed, clock icon. A schedule-only
  group is not emptied (that's what keeps nearby non-empty).
- **Card order — the same global rule (3):** live cards (by nearest live-ETA) above
  all schedule-only cards (by nearest ETA).
- Clickability (follow live / open the stop) — unchanged (`nearbyGroupHasLive` /
  `nearbyFollowTarget`).

### 6. Far times — an absolute arrival time
An ETA **≥ `kFarEtaMinutes` (= 60)** is shown as an **arrival time** (`02:45`, 24h,
formatted by the app locale), not minutes — "75 min" isn't computed in the head
anymore. The threshold 60 is a named constant with a comment
(`core/eta_format.dart → etaLabel`).
Applied **everywhere** an ETA is rendered: shutter rows, the collapsed Scheduled
cell (incl. its **secondary** times), nearby cards. Below the threshold — "Now"
(≤0) / "N min", as before.

### Scope
The **stop shutter** (in-app — the `stop_sheet.dart` bottom sheet; the same render
is mirrored by `StopScreen` for the deep link `/stop/:id`) **and the Nearby
shutter** (5). The mini-map and Planned rows on a complete absence of live (Phase-1
behaviour) are **outside** this change.
