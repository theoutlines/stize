# Stigla

Real-time Belgrade public transport app — iOS, Android, and Web from a single Flutter codebase.

> Unofficial app. Not affiliated with JKP Upravljanje javnim prevozom Beograd.

## What it does

- Live arrivals for your favorite stops, refreshed automatically.
- Search by stop name, street/place, or line number.
- Map view with stop markers and (where the data allows) animated vehicle tracking.
- In-app feedback board — no accounts required.

## Repo layout

```
backend/   Cloudflare Worker API (proxy + cache + normalization layer)
app/       Flutter app (iOS / Android / Web)
```

## How it works

The app never talks to the upstream data source directly. It only calls this
project's own backend, which caches responses (stale-while-revalidate, ~30s TTL
per stop) and normalizes them into a stable API contract. See `backend/README.md`
for the full contract and `backend/.env.example` for required configuration.

Stop and line reference data (names, routes, shapes) comes from the official
Belgrade GTFS feed (data.gov.rs), not from the live-arrivals source.

## Status

Personal project, built in stages. Not intended for wide public distribution.

## License

TBD.
