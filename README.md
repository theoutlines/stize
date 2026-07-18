# Stigla

Real-time Belgrade public transport, from one Flutter codebase — iOS, Android, and Web.

> Unofficial app. Not affiliated with JKP Upravljanje javnim prevozom Beograd.

Stigla answers the two questions a rider at a stop actually has: **what's coming
and when**, and **which vehicle am I about to board — and can I trust it?** It is
deliberately *not* a journey planner: no A→B routing, just live arrivals, the
vehicles themselves, and how reliable the picture is.

## What it does

- **Live map** — vehicles rendered as a batched GPU symbol layer and animated
  smoothly along their route between GPS fixes (no teleporting, no drift), each
  stitched to the direction it's actually travelling.
- **Arrivals** — live board for any stop; when the live feed is thin (night,
  inter-peak) it's backfilled with GTFS **schedule** departures so a stop is
  never blank. Scheduled vehicles also appear on the map where a line has no
  live one.
- **Nearby** — a location-first list of every line you can catch around you,
  ordered by time-to-board (walk to the stop + wait for the soonest catchable
  departure), not bare ETA.
- **Vehicle type classification** (bus / trolleybus / tram) consistent between
  stops, lines, and moving markers.
- **Coverage heatmap** of route density on the main map when zoomed out.
- **Search** by stop name, street/place, or line number.
- **In-app feedback board** — no accounts required.
- Localized **EN / RU / SR**.

## Stack

- **App** — Flutter, web-first (CanvasKit), also iOS & Android. MapLibre GL +
  MapTiler vector tiles.
- **Backend** — Cloudflare Worker (Hono, TypeScript) + D1 + KV, a
  proxy/cache/normalization layer over a fragile upstream transit feed.
- **Reference data** — the official Belgrade GTFS feed (stop names, line
  metadata, route shapes, timetables), rebuilt into a compact bundle.

```
backend/   Cloudflare Worker API (proxy + cache + normalization)
app/       Flutter app (iOS / Android / Web)
```

## How it works

The app never talks to the upstream data source directly — it only calls this
project's own backend, which caches responses (stale-while-revalidate, ~30s TTL
per stop, capped to ~1 upstream request per 30s per key) and normalizes them into
a stable versioned API. Stop/line/shape/timetable reference data comes from the
official Belgrade GTFS feed, not the live-arrivals source. See `backend/README.md`
for the API contract and `backend/.env.example` for required configuration.

## Running locally

You'll need a (free) MapTiler API key to render maps.

```sh
# Backend (Cloudflare Worker)
cd backend
npm install
cp ../.env.example .dev.vars     # fill in real values
npm run dev                      # http://localhost:8787

# App (Flutter) — MapTiler key via a gitignored dart_defines.json
cd app
flutter run --dart-define-from-file=dart_defines.json                      # default device
flutter run -d chrome --dart-define-from-file=dart_defines.json            # web
```

`dart_defines.json` is `{ "MAPTILER_KEY": "…" }` and is gitignored (it's a client
key — restrict it by allowed origins in the MapTiler dashboard). Point the app at
a local backend with `--dart-define=API_BASE_URL=http://localhost:8787`.

## Privacy

Stigla has **no accounts and no tracking of people.** It uses no third-party
analytics, no Google Analytics, no advertising or fingerprinting SDKs — nothing
that ships your data to someone else.

To understand which features are worth keeping, the app records a small set of
**anonymous product events** (e.g. "a stop was opened", "a vehicle was
followed", "the app was opened") to *our own* backend. By design these carry
**no way to identify you**:

- **no** user id, account, or device fingerprint;
- **no** IP address or precise location stored with an event;
- **no** free text — only fixed, enumerated values (e.g. the *class* of your
  system language — Serbian / Russian / English / other — never anything more
  specific);
- timestamps are coarsened to the **hour**, not the second.

The only link between events is an **ephemeral, random id kept in memory for the
current tab** (never written to disk, never an identity) so we can tell that
"open stop → follow vehicle" was one sequence. It's gone the moment the tab
closes. Data collection is **off by default** and, when on, the data stays ours —
we don't sell it or hand it to a third party. The exact event list and the
enum-only properties live in
[`backend/src/lib/productAnalytics.ts`](backend/src/lib/productAnalytics.ts).

## Contributing & license

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — ground rules and setup.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how it's built + non-obvious gotchas.
- [`CHANGELOG.md`](CHANGELOG.md) — human-readable history.
- Licensed under **AGPL-3.0** — see [`LICENSE`](LICENSE).
