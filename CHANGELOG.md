# Changelog

Notable, human-readable changes to Stigla. Newest first. This is the product
history (what changed for riders and developers), not a commit log.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

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
