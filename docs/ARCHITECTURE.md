# Architecture & conventions

How Stigla is put together, and the non-obvious gotchas worth knowing before you
touch the map or the backend. For setup and run commands see the
[README](../README.md) and [CONTRIBUTING](../CONTRIBUTING.md).

The client **only ever calls its own backend** — never the upstream transit
source directly.

## Backend — a proxy/cache/normalization layer

The Worker (`backend/src/index.ts`, Hono) turns a fragile, undocumented upstream
source into a stable versioned API under `/api/v1`. Key pieces:

- **Data provider** (`src/lib/transitProvider.ts`): the upstream live-arrivals
  source is hidden behind a `TransitDataProvider` interface; its concrete
  endpoint/params live **only in env vars** (`TRANSIT_SOURCE_*`), never in
  source. The upstream is **per-stop only** (POST with a stop id) and returns,
  per vehicle, GPS + `stations_between` + `garage_no` + `all_stations` (full
  ordered route geometry).
- **SWR cache** (`src/lib/swrCache.ts`): stale-while-revalidate over
  `caches.default`. Callers get an instant response; a background
  `ctx.waitUntil()` refresh keeps it fresh, capped at ~1 upstream request per
  30s **per cache key, globally** (not per user), with exponential backoff on
  failure. Respect this — never bypass it or poll the upstream faster.
- **GTFS reference data** (`scripts/build-gtfs.mjs` → `public/gtfs/`, served via
  `env.ASSETS`): stop names/coords, line metadata, per-route shapes, and
  precomputed timetables come from the official GTFS feed, **not** the live
  source.
- **Vehicles-in-area** (`src/lib/vehicles.ts`, `GET /api/v1/vehicles/nearby`):
  the upstream has no "all vehicles in a bbox", so this reconstructs it by
  fanning out to nearby stops' arrivals and deduping by `garage_no`. The
  fan-out is bounded (≤18 stops, ≤1500 m) and rides the shared 30s cache. Each
  vehicle's travel `heading` and its actual-direction `route_id` are resolved
  here from the `all_stations` route segment it sits on (route-based, so stable
  vs. a GPS delta).
- **Schedule fallback** (`src/lib/arrivals.ts` + `src/lib/schedule.ts`): when the
  live feed is thin, the arrivals list is backfilled with GTFS scheduled
  departures (deduped against live). The map similarly emits scheduled objects
  for lines with no live vehicle. The per-stop schedule cost is one uncached
  subrequest per stop, so it's applied only where the fan-out stays small — the
  wide vehicles-in-area fan-out deliberately skips it to stay under the
  per-invocation CPU/subrequest limits.
- **Nearby** (`src/lib/nearbyArrivals.ts`, `GET /api/v1/arrivals/nearby`):
  reuses the same `nearbyStops` fan-out + `getArrivals` (live + schedule),
  grouped by line + direction and deduped to the closest stop.
- **Kill switch** (`src/lib/killswitch.ts`, KV flag): when set, `/arrivals`
  returns `service_status: "unavailable"` without touching the upstream.
- **Ideas** (D1) and **experimental route alerts** (`src/lib/alerts.ts`, scrapes
  the public transit news site and uses an LLM to extract structured JSON,
  refreshed by a daily Cron trigger).
- **Feature flags** live in KV and flip without a redeploy — see
  [`feature-flags.md`](feature-flags.md).

## App — layered Flutter (`app/lib/`)

`data/` (repos + API client + local caches) → `domain/` (models + repository
interfaces) → `presentation/` (Riverpod providers, go_router, screens/widgets).

- **API access**: everything goes through `data/api/stigla_api_client.dart`
  (base URL from `core/api_config.dart`, overridable via `API_BASE_URL`).
  Repositories fall back to an on-device GTFS mirror
  (`data/local/gtfs_offline_cache.dart`) **only on `NetworkException`**.
- **Wiring**: providers in `presentation/providers/providers.dart`, routes in
  `presentation/router.dart`. The root is a single Scaffold with a left drawer
  (`widgets/app_drawer.dart`) over an `IndexedStack` of the map and Ideas.
- **Map stack** (MapLibre + MapTiler vector tiles): `core/map_style.dart`
  (theme-synced style URLs); `core/map_support.dart` (per-type classification,
  the `VehicleMarker` pill, `kMapRenderingEnabled` flag). Moving vehicles on the
  main map render as a **batched GPU symbol layer** (`core/moving_object_layer.dart`)
  — one GeoJSON source, sub-linear in vehicle count. The `VehicleMarker` widget
  is still used by the per-stop "vehicles approaching this stop" mini-map
  (`widgets/live_vehicles_map.dart`).
- **Vehicle movement**: `core/vehicle_track_animator.dart` holds the pure
  interpolation math (kept separate so it's unit-testable). The backend sends a
  forward timing plan (`trajectory` + `as_of`); markers play it forward by time
  along the route shape, and a vehicle without a usable plan eases conservatively
  toward its latest fix (never past it), with a "looks stuck" staleness
  heuristic. `core/vehicle_route.dart` splits a route into travelled/upcoming and
  derives per-stop ETAs.

## Conventions & non-obvious gotchas

- **Never call the upstream source from client code**, and never hardcode its
  URL/params anywhere — they live only in `backend/.dev.vars` (local) /
  Cloudflare secrets (prod). The MapTiler key is a client key (it ships in the
  web bundle — restrict it by Allowed origins in the MapTiler dashboard); keep
  it in the gitignored `app/dart_defines.json`.
- **Every new backend route needs an explicit Hono route to get CORS headers.**
  Cloudflare's static-asset binding serves `/gtfs/*.json` directly and bypasses
  the `cors()` middleware. A browser "Failed to fetch" on a *new* path is
  almost always this.
- **Verify a web deploy by sha, not the browser.** The custom domain sits behind
  a Cloudflare zone whose Browser Cache TTL rewrites cache headers, so the
  browser HTTP cache lies. Confirm by curl+sha256 of `main.dart.js` against the
  local `build/web/main.dart.js`. The `pages.dev` alias and the custom domain
  propagate a few minutes apart.
- **Client vehicle polling must stay ≥30s** (matched to the backend cache).
  Faster polling re-reads identical cached positions, which the movement
  heuristic misreads as "stuck".
- **Riverpod**: use `AsyncValue.valueOrNull`, not `.value` — `.value` *rethrows*
  in an error state and will crash the widget instead of showing an offline/
  empty state.
- **Map render bug on web? Two observation channels — use both, console FIRST.**
  The map runs on Flutter-CanvasKit, so the map/layers are **not** in the DOM and
  JS map-object inspection is unreliable/blind. Instead: (1) the **browser
  console** still catches real exceptions (`JSON.parse`/`SyntaxError`, tile/style
  errors) — a whole class of "the layer exists but has no features / nothing
  renders" bugs sits there as a red error; (2) a **staging-only stop diagnostics
  overlay** (`home_map_screen._stopDiagnosticsOverlay`, gated on `isStaging`,
  invisible in prod) prints the render pipeline from inside the app — gate flags,
  viewport fetch, marker counts, which stop layers are on the map, and whether
  each type actually draws at a stop's pixel. It reads state Flutter won't expose
  to JS.
- **Serialize GeoJSON for map sources with `dart:convert` `jsonEncode`, never
  geobase's `FeatureCollection.toText()`.** `toText()` does **not** escape `"`
  (and other specials) in string properties; ~19 Belgrade stops have a quote in
  their name (`Park "Tašmajdan"`, `OŠ "Dragojlo Dudić"`, …), so `toText()` emits
  invalid JSON and the maplibre-web plugin's `updateGeoJsonSource →
  setData(JSON.parse(data))` throws, leaving that source empty. This also means a
  **declarative** `MarkerLayer`/`PolylineLayer` (which the plugin serializes with
  `toText()` internally) must not carry a quotable string property like a stop
  `name` — keep only `stopId` and look the name up on tap. See
  `home_map_screen._pushStopSources` + `test/stop_geojson_test.dart`.
- **Positional vs imperative map layers.** Stop layers are added imperatively
  (bypassing the plugin's positional `LayerManager`) so they interleave
  correctly with the vehicle symbol layer; getting the layer order wrong makes
  layers vanish.
- **Tests and the map**: `MapLibreMap` throws `UnsupportedError` under
  `flutter test`; the `kMapRenderingEnabled` flag makes map widgets render
  placeholders. Widget tests that pump a screen with a map must set it false.
- **Sheets/overlays over the web map need a pointer barrier.** The map is a web
  platform view; a draggable sheet or overlay placed over it must be wrapped in
  `PointerInterceptor`, or scroll/drag gestures leak through to the map
  underneath and pan/zoom it.
- **Staging previews must bake both defines.** A build meant for staging must set
  `API_BASE_URL=<staging backend>` **and** `ENVIRONMENT=staging`; otherwise it
  silently points at prod (where in-dev flags are OFF) and you get the pre-flag
  render with no error. `ENVIRONMENT=staging` also shows a visible **STAGING**
  badge — the quick eyeball check that a preview is on the staging backend.
- The Android release keystore (gitignored) must stay stable across releases —
  regenerating it breaks update installs.
- Code and comments are English; the app UI is localized EN/RU/SR via
  `app/lib/l10n/*.arb` (edit all three, then `flutter gen-l10n`).
