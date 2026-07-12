# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Stigla is a real-time Belgrade public transport app: one Flutter codebase
(`app/`, iOS/Android/Web) talking to a Cloudflare Worker backend (`backend/`).
The client **only ever calls its own backend** — never the upstream transit
source directly.

## Commands

### Backend (`backend/`, TypeScript / Hono on Cloudflare Workers)
```sh
npm install
cp ../.env.example .dev.vars     # fill real values; gitignored, never commit
npm run dev                      # wrangler dev (local, http://localhost:8787)
npm test                         # vitest, runs in the real Workers runtime
npx vitest run test/transitProvider.test.ts   # a single test file
npx vitest run -t "derives a heading"         # a single test by name
npx tsc --noEmit                 # typecheck
npm run deploy                   # wrangler deploy (prod worker)
npm run gtfs:build               # rebuild public/gtfs/ from a fresh feed (see backend/README.md)
```

### App (`app/`, Flutter)
The MapTiler key is required to render maps and is injected at build time from
a **gitignored** `app/dart_defines.json` (`{"MAPTILER_KEY": "..."}`):
```sh
flutter run --dart-define-from-file=dart_defines.json                 # default device
flutter run -d chrome --dart-define-from-file=dart_defines.json       # web
flutter run --dart-define-from-file=dart_defines.json \
  --dart-define=API_BASE_URL=http://localhost:8787                    # point at a local worker
flutter test                                   # all tests
flutter test test/vehicle_route_test.dart      # a single test file
flutter analyze lib test                       # lint/analyze
flutter gen-l10n                               # regenerate localizations after editing lib/l10n/*.arb
flutter build web --release --dart-define-from-file=dart_defines.json # prod web bundle
```

### Deploying web to prod (Cloudflare Pages, project "stigla")
```sh
# from app/, after `flutter build web --release --dart-define-from-file=dart_defines.json`
npx wrangler pages deploy build/web --project-name=stigla --branch=main         # production
npx wrangler pages deploy build/web --project-name=stigla --branch=preview-<x>  # preview alias <x>.stigla.pages.dev
```

## Architecture

### Backend — a proxy/cache/normalization layer
The Worker (`src/index.ts`, Hono) turns a fragile, undocumented upstream source
into a stable versioned API under `/api/v1`. Key pieces:

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
  `env.ASSETS`): stop names/coords, line metadata, and per-route shapes come
  from the official GTFS feed, **not** the live source.
- **Vehicles-in-area** (`src/lib/vehicles.ts`, `GET /api/v1/vehicles/nearby`):
  the upstream has no "all vehicles in a bbox", so this reconstructs it by
  fanning out to nearby stops' arrivals and deduping by `garage_no`. The
  fan-out is bounded (≤12 stops, ≤1500 m) and rides the shared 30s cache. Each
  vehicle's travel `heading` is computed here from the `all_stations` route
  segment it sits on (route-based, so it's stable vs. a GPS delta).
- **Kill switch** (`src/lib/killswitch.ts`, KV flag): when set, `/arrivals`
  returns `service_status: "unavailable"` without touching the upstream.
- **Ideas** (D1 `stigla-ideas`) and **experimental route alerts**
  (`src/lib/alerts.ts`, scrapes bgprevoz.rs and uses Claude Haiku to extract
  structured JSON, refreshed by a daily Cron trigger).

### App — layered Flutter (`app/lib/`)
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
  (theme-synced style URLs), `core/map_support.dart` (custom marker widgets,
  the `VehicleMarker` pill, per-type classification, `kMapRenderingEnabled`
  flag). Live vehicles render as `WidgetLayer`/`Marker` (real Flutter widgets
  tracked to geo points), not sprite images.
- **Vehicle tracking**: `core/vehicle_track_animator.dart` holds the pure
  interpolation math (kept separate so it's unit-testable) — a marker only
  eases toward the latest real fix, never past it — plus a "looks stuck"
  staleness heuristic. `core/vehicle_route.dart` splits a route into
  travelled/upcoming and derives per-stop ETAs. `home_map_screen.dart` shows
  vehicles across the viewport; `widgets/live_vehicles_map.dart` shows the
  vehicles approaching one stop.

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
- **Verify a web deploy by sha, not the browser.** The `stigla.theoutlines.xyz`
  custom domain sits behind a Cloudflare zone whose Browser Cache TTL rewrites
  cache headers, so the browser HTTP cache lies. Confirm by curl+sha256 of
  `main.dart.js` against the local `build/web/main.dart.js`. The `pages.dev`
  alias and the custom domain propagate a few minutes apart.
- **Client vehicle polling must stay ≥30s** (matched to the backend cache).
  Faster polling re-reads identical cached positions, which the movement
  heuristic misreads as "stuck".
- **Riverpod**: use `AsyncValue.valueOrNull`, not `.value` — `.value` *rethrows*
  in an error state and will crash the widget instead of showing an offline/
  empty state.
- **Tests and the map**: `MapLibreMap` throws `UnsupportedError` under
  `flutter test`; the `kMapRenderingEnabled` flag makes map widgets render
  placeholders. Widget tests that pump a screen with a map must set it false.
- The Android release keystore (`app/android/keystore/stigla-release.jks`,
  gitignored) must stay stable across releases — regenerating it breaks update
  installs.
- Code and comments are English; the app UI is localized EN/RU/SR via
  `lib/l10n/*.arb` (edit all three, then `flutter gen-l10n`).

## Процесс

### Истина — в файлах, не в чатах
Всё важное живёт в репозитории: спеки, промпты задач, отчёты, бэклог.
Чат-сессии одноразовые; любая новая сессия должна восстанавливать контекст
из CLAUDE.md и docs/, а не из истории переписки.

### Карта документов
- `CLAUDE.md` — конституция проекта (этот файл).
- `docs/BACKLOG.md` — продуктовый бэклог и роадмап. Единственный источник приоритетов.
- `docs/*.md` — спеки фич (`FLEET_INTEGRATION.md` и др.).
- `docs/prompts/` — постановки задач (промпты), по одной на файл.
- `docs/reports/` — отчёты по выполненным задачам: `YYYY-MM-DD-<task>.md`, на русском.
- `assets/data/` — данные приложения (`fleet_models.json` и др.) — это НЕ документация.

### Ветки и worktrees
- `main` всегда стабильная и релизится в любой момент. Недоделанное попадает
  в main только выключенным за фиче-флагом.
- Каждая задача — своя ветка: `feature/<имя>` или `fix/<имя>`.
- Одна сессия Claude Code = одна ветка = один git worktree (отдельная папка).
  Соглашение: `../stigla-<имя>` для `feature/<имя>`.
- Новый worktree: `git worktree add ../stigla-<имя> -b feature/<имя>`
  Удалить после merge: `git worktree remove ../stigla-<имя>` + `git branch -d feature/<имя>`

### Завершение задачи (definition of done сессии)
1. Код закоммичен в ветку задачи, тесты проходят.
2. Отчёт написан в `docs/reports/YYYY-MM-DD-<task>.md` (RU).
3. Если задача меняет приоритеты/статусы — отметить в `docs/BACKLOG.md`.
4. Отчёт обязан заканчиваться разделом «Как проверить» для владельца, не
   использующего терминал: всё, что требует команд (деплой staging,
   пересборка), сессия выполняет сама; владельцу — только URL, где взять
   доступы и что тыкать / что должно быть видно.
5. Merge в main — только по явной команде владельца.

### Браузер и веб-дашборды
Если задача упирается в веб-UI (MapTiler, Cloudflare dashboard и т.п.) — не
переносить действия на владельца. Подключиться к его браузеру: `/chrome`
(расширение Claude in Chrome, владелец залогинен на нужных сайтах). Сессия сама
выполняет действия в дашборде; владелец только подтверждает чувствительные шаги.
Логины/пароли сессия не вводит.

### Язык
Код и комментарии — EN. Отчёты, документация, коммуникация — RU.
