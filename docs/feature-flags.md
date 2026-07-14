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

In-development flags default **off on production** and **on on staging** (keyed on
`ENVIRONMENT`, see `defaultFor` in `featureFlags.ts`); an explicit KV value always
overrides the default.

## Registry — the single source of truth (keep this current)

Every flag in `backend/src/lib/featureFlags.ts` **must** have a row here. State as
of **2026-07-14** (verified against prod/staging KV — see
`docs/reports/2026-07-14-flags-audit.md`). Status: **permanent** = lives behind a
flag by design; **rollout** = shipped & stable, flag now redundant → removal
candidate; **fresh** = recently shipped, kept for instant rollback.

| flag | gates (feature / screen) | prod | staging | introduced | status |
|---|---|---|---|---|---|
| `analytics_collect` | worker logs arrival observations to build history (backend) | ON | ON | 2026-07-10 | permanent (control) |
| `analytics_show` | reveals the (draft) analytics screens (client) | OFF | ON | 2026-07-10 | permanent (draft UI) |
| `coverage_map_show` | coverage-map tab, static heatmap infographic (client) | OFF | ON | 2026-07-12 | permanent (experiment, dormant) |
| `coverage_on_main_map` | coverage heatmap overlay on the main map when zoomed out (client) | OFF | ON | 2026-07-12 | permanent (experiment, dormant) |
| `nearby_list` | the "Nearby" draggable sheet over the map (client) | ON | ON | 2026-07-12 | fresh (kept for rollback) |
| `nearby_sort_board` | "Nearby" ordered by time-to-board instead of bare ETA (backend) | ON | ON | 2026-07-12 | fresh (kept for rollback) |
| `symbol_layer` | moving vehicles render as a MapLibre GPU symbol layer (client) | ON | ON | 2026-07-13 | rollout → removal candidate |
| `live_position_only` | map draws only vehicles with a real live GPS (client) | ON | ON | 2026-07-13 | rollout → removal candidate |
| `schedule_fallback` | schedule tail in the arrivals list; client renders scheduled rows (backend+client) | ON | ON | 2026-07-14 | rollout → removal candidate |
| `schedule_map` | scheduled objects on the map where a line has no live vehicle (backend) | ON | ON | 2026-07-14 | rollout → removal candidate |

Config parameters (KV, not boolean flags):

| key | controls | prod | staging | default |
|---|---|---|---|---|
| `config:nearby_schedule_stops` | how many nearest "Nearby" stops inherit the schedule fallback (CPU cap) | 5 | 5 (default) | 5 (clamp 0..8) |

Notes: the two analytics flags are independent on purpose — turn **collect** on
early to accumulate history while **show** stays off. `nearby_sort_board` only
matters when `nearby_list` is on. `schedule_map` needs `schedule_fallback` too for
scheduled buses to appear on the map.

### Registry maintenance (part of task DoD — see CLAUDE.md)

- **New flag** → add it to `featureFlags.ts` **and** a row here (gates / prod /
  staging / date / status) in the same task.
- **Feature stabilised, flag no longer needed** → when you remove the flag from
  code, remove its row here too (and delete the KV keys).
- Keep the state column honest: it should match prod/staging KV. Re-verify during
  any flag audit.

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
