# Contributing

This is primarily a personal project with a small circle of collaborators, but
issues and PRs are welcome.

## Licence of contributions

By opening a PR you agree that your contribution is licensed under AGPL-3.0
together with the store-distribution permission in
`LICENSE-STORE-EXCEPTION.md` (so the app can be shipped through the App Store
and Google Play).

## Ground rules

- Never commit secrets. Copy `.env.example` to a local `.env` (or use
  `wrangler secret put`) and keep real values out of the repo.
- The app must only talk to its own backend (`backend/`) — never call the
  upstream transit data source directly from client code.
- Keep the backend's data-provider interface abstract: the concrete upstream
  endpoint and its parameters live in environment variables, not in source.
- Respect the upstream source: rate limit requests, send a descriptive
  `User-Agent` with a contact email, back off on errors, and avoid parallel
  request storms.
- Stop and line reference data comes from the official GTFS feed
  (data.gov.rs), not from the live-arrivals proxy.

## Branching

- `main` is always releasable — never merge unfinished work into it.
- One branch per task: `feature/<name>` for features, `fix/<name>` for bugs.
- Merge (or PR) a branch into `main` only once it's done and tested. Small
  fixes and a large feature can proceed on separate branches without colliding.

Day-to-day:

```sh
git checkout main && git pull                 # start from the latest stable
git checkout -b feature/my-thing              # new task on its own branch
# …work, commit on the branch…
git checkout main && git merge feature/my-thing   # land it when tested
git branch -d feature/my-thing                # tidy up
```

Releasing from `main` is independent of any in-progress branch: large features
ride in `main` dormant behind a flag, so releases can ship before the feature is
finished.

## Feature flags

Remotely-togglable flags live in Cloudflare KV (same mechanism as the kill
switch) and flip **without a redeploy**. The list of flags lives in
`backend/src/lib/featureFlags.ts`.

## Environments

Production (`main`, flags off) and a separate **staging** web contour (dev flags
on, isolated KV/D1, STAGING badge) for testing unreleased features.

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how the backend and app
fit together and the non-obvious gotchas (map rendering on CanvasKit, GeoJSON
escaping, caching, `PointerInterceptor`, staging defines, …). Read it before
touching the map stack or adding a backend route.

## Code style

- Code and comments: English.
- Keep changes scoped — avoid unrelated refactors in the same PR.

## Keep the docs current

- **Notable change → a line in [`CHANGELOG.md`](CHANGELOG.md)** (English,
  product-facing: what a rider or developer got, not how it was debugged).
- **Add or remove a feature flag** in `backend/src/lib/featureFlags.ts` (and
  delete its KV keys when a flag is retired).

## Local setup

See `backend/README.md` and `app/README.md` (added as those stages land).
