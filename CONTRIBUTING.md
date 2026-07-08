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

## Code style

- Code and comments: English.
- Keep changes scoped — avoid unrelated refactors in the same PR.

## Local setup

See `backend/README.md` and `app/README.md` (added as those stages land).
