# Changelog

Notable, human-readable changes to Stiže. Newest first. This is the product
history (what changed for riders and developers), not a commit log.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## 2026-11-24

### Changed
- **No phantom arrivals.** A timetable departure is shown only if its trip has
  not left the terminus yet. A trip already on the road without a live vehicle
  either runs untracked or doesn't run, so it is no longer listed ("tram 5 in
  1 min" at a stop 11 min from the terminus). Scheduled vehicles are no longer
  drawn on the map at all, for the same reason.
- **Stop header:** the star button and the "Something wrong with this stop?"
  row are gone. A More button right after the stop name holds Add to My Stops,
  Share stop and Report a problem; a small star after the name shows the stop
  is in My Stops. The list ends with its last card.
- **Line filter:** "All lines" is picked by default; unpicked line chips are
  neutral and a picked one takes its line colour. From "All lines" a tap picks
  just that line, further taps add or remove lines. Only lines with an arrival
  get a chip.

### Removed
- **By time / By comfort sort** on the stop board. Comfort badges stay on the
  cards.

## 2026-11-22

### Added
- **Stiže design system (behind the `ds_stize` flag)** — the app's own design
  system, forked from the Growth Test Planner's: Uncut Sans everywhere, a 4px
  grid, dark and light themes, a signal-green accent and a separate transit
  colour layer. Tokens live in `design/tokens/` and generate the Flutter theme.

### Changed
- **Trolleybus orange** is slightly darker (`#E8701A`) so white line numbers
  read on it.

### Removed
- **Russian UI.** The app now ships English and Serbian (Latin). Devices set to
  Russian fall back to English; a saved Russian choice resets to "System".
- **Legacy `theoutlines.xyz` addresses retired** — Stiže now lives entirely on
  its own domain (web `stize.app`, API `api.stize.app`, staging API
  `api-staging.stize.app`). All three old `theoutlines.xyz` hosts —
  `stigla.theoutlines.xyz` (redirect), `stigla-api.theoutlines.xyz` (prod API)
  and `stigla-api-staging.theoutlines.xyz` (staging API) — no longer resolve.
  There are no external clients, so nothing migrates. (Infrastructure names stay
  `stigla-*`; only the public `theoutlines.xyz` hostnames were removed.)

## 2026-07-21

### Added
- **Drawer "about & contact" footer** — an in-app feedback form (a message + an
  optional contact; the email is never exposed), a link to public GitHub issues,
  open-source licenses (AGPL-3.0), an in-app privacy policy, an optional donate
  link, and a dimmed version line. The feedback form ships behind a flag, off on
  prod until reviewed.
- **Desktop panel collapse** — a Google-Maps-style tab collapses the context
  panel to the screen edge and back; the search and burger float above it as
  separate islands, and the map reclaims the space when collapsed.

### Changed
- **Rebrand: Stigla → Stiže, live on [stize.app](https://stize.app)** — the
  product is now **Stiže** (Serbian for "arrives"). The app name updates
  everywhere it's shown (EN/RU/SR, title, PWA install name, About), and prod
  serves from `stize.app` (API `api.stize.app`). The old
  `stigla.theoutlines.xyz` address keeps working and 301-redirects to `stize.app`
  with the path preserved, so existing bookmarks and deep links migrate cleanly.
  Internal infrastructure names are unchanged.
- **Global search everywhere** — the mobile nearby sheet uses the same search as
  desktop: nearby matches first, then stops/lines; it works even before location
  is enabled.
- **Unified bottom sheets** — stop, vehicle-info and "About the vehicle" are one
  full-width sheet with a shared handle and detents; "About the vehicle" opens
  in-place with a back arrow (no separate modal); the map shifts up so the stop
  stays visible above the sheet.

## 2026-07-20

### Added
- **Vehicle-mode toggle** — on-demand vehicles (shown only in context: a tapped
  stop's arrivals and a followed vehicle) is now the default, with a single map
  toggle to switch back to the background "aquarium." The choice persists locally.
- **Adaptive context panel** — on desktop the nearby / stop / vehicle views become
  a persistent left panel beside a full-height map with a global search; on mobile
  they stay as unified bottom sheets with one back-navigating flow.
- **ETA-change badge** — the stop shutter flags when a vehicle's predicted arrival
  time shifts, diffed against the absolute arrival time (not ticking minutes).

### Changed
- **Arrivals list dedup** — live and scheduled rows of the same line no longer
  double-count; scheduled entries collapse into one cell, and the list is ordered
  so nothing scheduled ever sits above a live arrival.

### Behind the scenes (not yet rider-visible)
- **Anonymous product analytics** — a small set of enumerated, identity-free usage
  events (see the Privacy section of the README), collection off by default.
- **Citywide reliability history** — a background sentinel sweep so accumulated
  history covers every line, not just the stops riders open; plus a v2 analytics
  aggregate (per direction, headway histograms, best-effort schedule delay). The
  screens that surface it are still off.
- **Tram-jam detection groundwork** — the backend now records the data needed to
  detect a whole tram line stalling on one segment; the rider-facing warnings stay
  behind a flag until the thresholds are calibrated on a real jam.

## 2026-07-14

### Added
- **GPU vehicle rendering** — moving vehicles are drawn as a single batched
  MapLibre symbol layer (sub-linear in vehicle count) instead of per-vehicle
  widgets.
- **Smooth vehicle movement** — markers extrapolate forward along the route
  between fixes (no 30-second freezes), stay anchored to the real GPS fix (no
  drift), and follow a backend-provided timed trajectory.
- **Schedule fallback** — the arrivals list backfills GTFS scheduled departures
  when live data is thin, so a stop is never blank; scheduled vehicles also
  appear on the map where a line has no live one.
- **Nearby** — a location-first list of catchable lines around you, ordered by
  time-to-board (walk + wait) rather than bare ETA.
- **Suburban lines** merged into the feed alongside city lines.
- **Vehicle type classification** (bus / trolleybus / tram) unified across
  stops, lines, and markers.
- **Coverage heatmap** on the main map when zoomed out.

### Fixed
- **Vehicle direction** — vehicles are stitched to the shape of the direction
  they're actually travelling, so they no longer appear to drive "through
  houses."
- **Stop rendering** — bus stops with quotes in their names no longer break the
  map source (GeoJSON is now escaped correctly); tram stops always show the tram
  icon.
- **Placeholder vehicles** — schedule-derived placeholder rows (no real GPS)
  stay in the arrivals list but no longer clutter the map.

### Changed
- Six stabilized rendering/data behaviors (GPU layer, timed movement, direction
  stitching, live-only map, schedule list + map) became the default and are no
  longer behind feature flags.

## 2026-07-12

### Added
- **Fleet identification** — from a vehicle's garage number, show its model,
  age, and comfort attributes (A/C, low-floor), so riders know what they're
  about to board.
- Coverage-map view (route-density heatmap).

### Fixed
- **Live geolocation** — the "my location" marker follows a continuous position
  stream and eases to each fix.
- **iOS web thermals** — the web app renders zero frames when nothing is moving
  (no more constant repaint).

## 2026-07-11

### Fixed
- Map/UX batch: correct route-leg projection for vehicles, honest geolocation
  errors, both directions of a line surfaced in search, empty-line filtering,
  and a fixed 30s refresh cadence.

## 2026-07-10

### Added
- Initial public transit app: live arrivals, stop/line search, map with stop
  markers, vehicle tracking, in-app feedback board, EN/RU/SR localization.
- Background arrival-history collection (for future analytics).
