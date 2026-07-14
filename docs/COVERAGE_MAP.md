# Coverage Map

Feature spec.

> Implemented as a **MapLibre heatmap**, not discrete lines.

## Why

A standalone infographic tab: glowing route corridors over a dark map
(reference: the Strava global heatmap). It answers "where does transit reach at
all, and where is there a lot of it?" — playful, screenshot-friendly, shareable.

It is **not navigation**: the layer plays no part in the core "what's coming to
my stop" flow; it lives on its own screen.

## Visual language

V0 is a **Strava-heatmap style**: the density of route points accumulates into a
heatmap. Overlapping routes = brightness (no per-feature weight).

- Base map is the same as the main map (`core/map_style.dart`), theme-synced
  (light/dark). No separate map style.
- Dark theme uses a warm density ramp: transparent → dark orange → orange →
  white (white only for the densest corridors: centre, bridges). Light theme
  uses a legible blue ramp.
- `heatmap-radius` and `heatmap-intensity` interpolate by zoom: at far zoom
  corridors merge into glowing zones (radius ≈ walking reach); at near zoom
  they're tighter and sharper. Intensity rises with zoom to compensate for
  points thinning out per pixel, so the core stays white and the edges dim.
- Criterion: on a "whole of Belgrade" view the eye can tell at least three
  levels apart — dim single branches on the outskirts / orange mid corridors /
  a white core.

Vehicle-type filter is a `filter` on the `type` property of the same heatmap
layer.

## Data and weight

Geometry comes from GTFS shapes (`public/gtfs/`). V0 doesn't touch backend
runtime — just a build script plus one CORS route to serve the file.

V0 weight = **point density** (how many routes run nearby). Algorithm:

1. Take the shapes of all routes (both directions of each line).
2. Sample each shape into points every ~90 m along the geometry
   (`scripts/build-coverage-points.mjs`).
3. Each route contributes its own points → where routes run together, local
   point density is higher. No separate corridor count is needed for rendering —
   density *is* the weight, and the heatmap layer sums it on the GPU.
4. The result is a precomputed `public/gtfs/coverage.geojson` (Point features,
   `type` property), served statically via `GET /api/v1/coverage`.

A collapsed corridor counter (`coverage-weighted.geojson`, `routes_count` +
`types`) is also produced but kept **out of the render path** — groundwork for
future weights. Not served or drawn in V0.

Future weights (not in V0): V1 = frequency from the GTFS timetable; V2 = actual
intensity from time-of-day/day-of-week aggregates plus a "how it usually is at
this hour" mode. The client reads named properties, so adding alternative
weights doesn't break the file or the client.

## UI

- A third screen in the `IndexedStack` (map / ideas / coverage), with a drawer
  item.
- V0 controls: vehicle-type filter (chips: all / tram / trolleybus / bus,
  multi-select) via a layer `filter`, no source rebuild. Space is reserved for a
  future "hour of day" control (not implemented).
- Legend: a **density gradient without numbers** ("rarer → busier"), matching
  the heatmap ramp.
- Default camera is the whole of Belgrade; position/zoom independent of the main
  map.
- Feature flag `coverage_map_show` (KV, like `analytics_show`): OFF on
  production, ON on staging. Hides the drawer item, the route, and the
  `IndexedStack` section.

## Performance

- The point GeoJSON loads once, the layer is static — no polling.
- ~90 m sampling: ~80k points, ~8.6 MB raw / ~0.5 MB gzip (within budget). If it
  needs to be lighter, use a coarser step (`STEP_METRES`) or two sources (coarse
  for far zoom, detailed for near).
- Type filtering is a layer `filter`/expression, no source rebuild.
- Serving is briefly edge-cached (`s-maxage=60`); the client appends `?rev=` to
  the source URL to bypass a stuck CDN cache when the data model changes.

## Definition of done

- The tab shows a coverage heatmap: dense corridors are clearly brighter than
  single lines; three density levels are distinguishable on the whole-city view.
- The type filter works; the theme switches with the rest of the app.
- The coverage file builds reproducibly from GTFS with one script
  (`npm run coverage:build`, part of `gtfs:build`).
- Behind a feature flag (`coverage_map_show=OFF` on production); `main` stays
  releasable.
