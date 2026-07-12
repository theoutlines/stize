# Feature flags & releasing dormant features

Stigla ships large features into `main` **before they're finished**, kept
dormant behind a remote flag, so ordinary releases keep flowing while the
feature matures. This is essential for analytics, where data collection must
start early (charts are worthless without accumulated history) but the screens
land later.

## Mechanism

Flags are stored in Cloudflare **KV** — the same remote, no-redeploy mechanism
as the kill switch (`backend/src/lib/killswitch.ts`). A flag is one KV key
(`flag:<name>`, value `"1"`/`"0"`). Flipping it is a single write; each worker
isolate reads the new value on its next request. **No rebuild, no redeploy.**

Defined in `backend/src/lib/featureFlags.ts`:

| flag | effect | default (prod / staging) |
|---|---|---|
| `analytics_collect` | the worker logs arrival observations to build history | off / on |
| `analytics_show` | the app reveals the (draft) analytics screens | off / on |
| `nearby_list` | the app shows the experimental "Nearby" list (a draggable sheet over the map) | off / on |
| `nearby_sort_board` | the "Nearby" list is ordered by **time-to-board** (walk to the stop + wait for the soonest catchable departure) instead of bare ETA | off / on |

In-development flags default **off on production** and **on on staging** (keyed on
`ENVIRONMENT`, see `defaultFor` in `featureFlags.ts`); an explicit KV value always
overrides the default.

The two analytics flags are independent on purpose: turn **collect** on early to
accumulate history while **show** stays off, then flip **show** once the screens
are ready. `nearby_sort_board` only matters when `nearby_list` is on — it swaps
the list's sort order (see `backend/src/lib/nearbyArrivals.ts`,
`timeToBoardMinutes`).

## Endpoints

- `GET /api/v1/config` → `{ version, flags: { … } }`, `cache-control: no-store`.
  The app fetches this at startup (`appConfigProvider`) and gates UI on it
  (`analyticsEnabledProvider`). Flags default to **off** if config is
  unreachable, so a dormant feature never leaks.
- `POST /api/v1/admin/flags` (header `X-Admin-Token: $ADMIN_TOKEN`):

  ```sh
  # turn data collection ON (do this early)
  curl -X POST https://stigla-api.theoutlines.xyz/api/v1/admin/flags \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -d '{"flag":"analytics_collect","value":true}'

  # reveal the screens LATER, when ready
  curl -X POST https://stigla-api.theoutlines.xyz/api/v1/admin/flags \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -d '{"flag":"analytics_show","value":true}'
  ```

## Releasing while a feature is unfinished

Because the feature's code sits in `main` but is inert until its flag is on, a
release from `main` is safe at any time:

- **Web (Cloudflare Pages):** build and deploy `main` as usual
  (`flutter build web` → `wrangler pages deploy`). Shipped screens stay hidden
  until `analytics_show` is flipped — no new deploy needed to reveal them.
- **Backend (Worker):** `npm run deploy` from `main`. Collection code is inert
  until `analytics_collect` is on.
- **Mobile (App Store / Play):** the build carries the dormant code; the flag
  reveals it over-the-air without shipping a new binary.

So: land collection early behind `analytics_collect`, keep shipping other
releases, and flip `analytics_show` when the screens are done.
