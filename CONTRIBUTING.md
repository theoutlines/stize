# Contributing

This is primarily a personal project with a small circle of collaborators, but
issues and PRs are welcome.

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

Releasing from `main` is independent of any in-progress branch — see
`docs/feature-flags.md` for how large features ride in `main` dormant (behind a
flag) so releases can ship before the feature is finished.

## Feature flags

Remotely-togglable flags live in Cloudflare KV (same mechanism as the kill
switch) and flip **without a redeploy**. See `docs/feature-flags.md`.

## Environments

Production (`main`, flags off) and a separate **staging** web contour (dev flags
on, isolated KV/D1, STAGING badge) for testing unreleased features. Addresses,
data isolation and the promote-to-prod steps are in `docs/staging.md`.

## Code style

- Code and comments: English.
- Keep changes scoped — avoid unrelated refactors in the same PR.

## Keep the docs current

- **Notable change → a line in [`CHANGELOG.md`](CHANGELOG.md)** (English,
  product-facing: what a rider or developer got, not how it was debugged).
- **Add or remove a feature flag → update the registry** in
  `docs/feature-flags.md` in the same change (and delete its KV keys when a flag
  is retired).

## Local setup

See `backend/README.md` and `app/README.md` (added as those stages land).
