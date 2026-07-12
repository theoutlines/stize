# Environments: production & staging

Two independent web environments share one codebase and one repo.

| | Production | Staging |
|---|---|---|
| Web | `stigla.theoutlines.xyz` | `staging.stigla.pages.dev` (link only) |
| API (worker) | `stigla-api.theoutlines.xyz` | `stigla-api-staging.theoutlines.xyz` |
| Worker | `stigla-backend` | `stigla-backend-staging` (`[env.staging]`) |
| KV / D1 | prod namespaces | **separate** staging KV + `stigla-{ideas,analytics}-staging` D1 |
| `ENVIRONMENT` | `production` | `staging` |
| In-dev feature flags | default **OFF** | default **ON** |
| Cron | daily | none |
| Marker | — | amber **STAGING** badge on every screen |

## Per-branch previews (private, one login for all)

Every branch you deploy to Pages gets its **own** persistent URL and they all
stay live at once — no switching:

```sh
# from app/, after building with the staging dart-defines:
npx wrangler pages deploy build/web --project-name=stigla --branch=<branch-name>
# → https://<branch-name>.stigla.pages.dev
```

So `feature-analytics.stigla.pages.dev` and `feature-<x>.stigla.pages.dev` can be
open in two tabs simultaneously. `staging.stigla.pages.dev` is just the alias for
the `staging` branch.

**All `*.pages.dev` previews are password-gated** by `app/web/_worker.js` (a
Pages advanced-mode worker). It only stores the **SHA-256** of the password —
never the plaintext — and gates only preview hostnames, so **production
(`stigla.theoutlines.xyz`) stays fully public**. The username + plaintext
password live in the team password manager (Basic Auth prompt, auto-filled).

To rotate the password: pick a new one, put its SHA-256 in
`PREVIEW_PASS_SHA256` in `app/web/_worker.js`, and redeploy.

## Data isolation

Staging is a fully separate worker (`wrangler [env.staging]`) bound to its **own**
KV and D1 databases, so it can never write to production feedback / ideas /
analytics. It has its own SWR cache but the same 1-request-per-30s cap to the
upstream source, and it's only used by one person — so no extra source load in
practice. The kill switch works per-environment (separate KV).

## Feature flags per environment

Flags live in each environment's own KV (same mechanism as the kill switch). When
a flag's KV key is **unset**, the default depends on `ENVIRONMENT`
(`backend/src/lib/featureFlags.ts`): **ON** on staging (so in-development features
are exercisable), **OFF** on production. An explicit KV value always overrides the
default, in either environment. `/api/v1/config` reports `environment` + `flags`.

## A branch = its own preview pair (no shared staging slot)

There is **no shared staging slot to deploy into anymore.** Do **not** run
`wrangler deploy --env staging` (`npm run deploy:staging`) from a feature
branch — that overwrites whatever version another branch put on
`stigla-api-staging.theoutlines.xyz`, which is exactly the collision this setup
removes. Instead, every branch that needs a live stand gets an **isolated pair**:

- **backend** — a *worker version*, not a deploy. `npm run staging:version`
  (wrapper over `wrangler versions upload --env staging`) uploads the current
  branch's code as a new version and prints its preview URL. It does **not**
  change which version serves live staging traffic — branch versions coexist.
- **frontend** — a Pages preview built against that version's preview URL.

```sh
# 1) From backend/: upload this branch as a worker version, capture its URL.
cd backend
PREVIEW_URL=$(npm run --silent staging:version | sed -n 's/^PREVIEW_URL=//p')
echo "$PREVIEW_URL"
# → https://<prefix>-stigla-backend-staging.theoutlines.workers.dev

# 2) From app/: build the web bundle pointed at that version, deploy a Pages
#    preview on a branch alias of your choosing (preview-<name>):
cd ../app && flutter build web --release \
  --dart-define-from-file=dart_defines.json \
  --dart-define=API_BASE_URL="$PREVIEW_URL" \
  --dart-define=ENVIRONMENT=staging
npx wrangler pages deploy build/web --project-name=stigla --branch=preview-<name>
# → https://preview-<name>.stigla.pages.dev  (STAGING badge, dev flags ON,
#    and every API call goes to *your* worker version, not the shared slot)
```

Two branches can each hold their own `preview-<name>.stigla.pages.dev` +
worker-version pair open at once; neither touches the other.

### What's shared vs. isolated between versions

Isolated per version: **the worker code** (each `versions upload` is its own
immutable bundle at its own URL). Shared across *all* versions of the staging
worker: **secrets and bindings** — the version inherits them from the worker, so
**the staging D1 databases, the staging KV namespace, and the SWR edge cache
(`caches.default`) are common to every branch's version.** Practical
consequences:

- A branch that **changes the D1 schema or the meaning of a KV flag** must not
  just upload a version — it would mutate shared staging state under every other
  branch's feet. Such a branch stops and coordinates it separately (that's a
  **[STOP & ASK]** in its own task prompt), or works on its own copy of the DB.
- The SWR cache is keyed by upstream request, so versions safely share cached
  upstream arrivals (same data, same 30s cap). But a branch that **changes the
  shape of the cached payload** can read an entry another version wrote and
  mis-parse it — treat a cache-shape change like a schema change.

### Preview URLs are public — no gate

Version preview URLs (`<prefix>-stigla-backend-staging.theoutlines.workers.dev`)
are **public and unauthenticated.** The unguessable hash prefix is not a
security boundary; the Pages password gate (`app/web/_worker.js`) lives on the
`*.pages.dev` frontend only and does **not** extend to the worker. This is fine
because the staging API is already public at
`stigla-api-staging.theoutlines.xyz` (CORS `*`, no per-user auth) — but the rule
follows: **never ship an endpoint with sensitive data or weakened auth onto a
preview version "because it's only staging."** If it's on a version, treat it as
on the open internet.

> **Cron doesn't run on preview versions.** Scheduled triggers only fire for the
> active deployment. Anything a branch needs from the daily Cron (analytics
> rollups, alert scraping) must be triggered by hand via the admin endpoint on
> the preview URL.

> Enabling this once (already done): Preview URLs must be **on** for
> `stigla-backend-staging` (Cloudflare dashboard → the worker → Settings →
> Domains & Routes → Preview URLs). The main workers.dev route stays **off** so
> the active `stigla-api-staging.theoutlines.xyz` deploy is untouched. If
> `npm run staging:version` prints no URL, that toggle got turned back off.

## Promoting a feature

When a branch is ready, promote to production (there's no permanent `develop`
branch — you go straight from a branch's preview pair to prod):

```sh
git checkout main && git merge <feature-branch> && git push
cd backend && npm run deploy                   # prod worker
cd ../app && flutter build web --release --dart-define-from-file=dart_defines.json
npx wrangler pages deploy build/web --project-name=stigla --branch=main
# dev flags stay OFF on prod until you flip them (admin/flags), no rebuild needed
```

> Note: the MapTiler key is origin-restricted. If the map is blank on
> `staging.stigla.pages.dev`, add that origin to the key's allowed origins in the
> MapTiler dashboard (analytics/list screens don't need it).
