# Stiže Backend

Cloudflare Worker that proxies and normalizes the upstream Belgrade transit
data source into a stable, versioned API. The client never talks to the
upstream source directly — only to this Worker.

Deployed at `https://api.stize.app` (legacy `https://stigla-api.theoutlines.xyz`
stays bound for already-shipped clients). The worker itself keeps its historical
name `stigla-backend` (renaming it would drop the deployment's bindings).

## Setup

```sh
npm install
cp ../.env.example .dev.vars   # fill in real values, never commit this file
npm run gtfs:build             # only needed after downloading a fresh GTFS feed
npm run dev                    # wrangler dev, local
npm test                       # vitest (runs in the actual Workers runtime)
npm run deploy                 # wrangler deploy
```

## Architecture

- **Data provider** (`src/lib/transitProvider.ts`): abstracts the upstream
  live-arrivals source behind a `TransitDataProvider` interface. The concrete
  endpoint/params live only in env vars (`TRANSIT_SOURCE_*`), never in source.
- **Cache** (`src/lib/swrCache.ts`): stale-while-revalidate on top of the
  Workers `caches.default` Cache API. Every request gets an instant response;
  a background `ctx.waitUntil()` refresh keeps data from drifting too far
  behind, capped at one upstream request per ~30s per cache key (globally,
  not per user). Repeated upstream failures back off exponentially instead of
  hammering a struggling source.
- **Kill switch** (`src/lib/killswitch.ts`): a KV flag (`service_killed`).
  When set, `/arrivals` returns `service_status: "unavailable"` without
  contacting the upstream source at all. Toggle via
  `POST /api/v1/admin/killswitch` with an `X-Admin-Token` header.
- **GTFS reference data** (`scripts/build-gtfs.mjs` → `public/gtfs/`): stop
  names, coordinates, line metadata, and per-route shapes/stop-sequences come
  from the official GTFS feed (data.gov.rs), not from the live-arrivals
  source, and are served as static assets (`env.ASSETS`).

## API

All endpoints are under `/api/v1`.

- `GET /arrivals?stop={stop_id}` — live arrivals for a stop.
- `GET /stops?query={text}` — search stops by name.
- `GET /stops/nearby?lat=&lon=&radius=` — stops within `radius` meters.
- `GET /lines?query={text}` — search lines by number.
- `GET /lines/{route_id}/shape` — route polyline + ordered stop list.
- `GET /lines/by-number/{line}/shape` — same, looked up by line number (e.g. `79`).
- `GET /geocode?query={text}` — Nominatim search, KV-cached.
- `GET /health` — `{ status: "ok" | "killed", version }`.
- `POST /admin/killswitch` — `{ "killed": boolean }`, requires `X-Admin-Token`.

## Refreshing the GTFS bundle

The raw feed (`backend/gtfs_raw/`) is gitignored — only the compact bundle in
`public/gtfs/` is committed. To refresh it against a newer GTFS export:

```sh
mkdir -p gtfs_raw/extracted
curl -L -o gtfs_raw/gtfs.zip "<latest GTFS zip URL from data.gov.rs>"
unzip -o gtfs_raw/gtfs.zip -d gtfs_raw/extracted
npm run gtfs:build
```
