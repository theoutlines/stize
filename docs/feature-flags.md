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

Every flag in `backend/src/lib/featureFlags.ts` **must** have a row here. Status:
**permanent** = lives behind a flag by design; **rollout** = shipped & stable,
flag now redundant → removal candidate; **fresh** = recently shipped, kept for
instant rollback.

| flag | gates (feature / screen) | prod | staging | introduced | status |
|---|---|---|---|---|---|
| `analytics_collect` | worker logs arrival observations to build history (backend) | ON | ON | 2026-07-10 | permanent (control) |
| `analytics_show` | reveals the (draft) analytics screens (client) | OFF | ON | 2026-07-10 | permanent (draft UI) |
| `coverage_map_show` | coverage-map tab, static heatmap infographic (client) | OFF | ON | 2026-07-12 | permanent (experiment, dormant) |
| `coverage_on_main_map` | coverage heatmap overlay on the main map when zoomed out (client) | ON | ON | 2026-07-12 | experiment, enabled in prod 2026-07-14 |
| `nearby_list` | the "Nearby" draggable sheet over the map (client) | ON | ON | 2026-07-12 | fresh (kept for rollback) |
| `nearby_sort_board` | "Nearby" ordered by time-to-board instead of bare ETA (backend) | ON | ON | 2026-07-12 | fresh (kept for rollback) |
| `vehicles_on_demand` | the map's vehicle-mode toggle — the user's choice between on-demand vehicles (in context only) and the background "aquarium" (client) | OFF | ON | 2026-07-15 | permanent (toggle gate + killswitch) — two-level, see below |
| `product_analytics` | anonymous product-usage events: client batches them to `POST /api/v1/events`, worker writes to `product_events` (client + backend) | ON | ON | 2026-07-18 | permanent (gate + killswitch) — enabled in prod 2026-07-19 (after `hour_bucket` privacy fix; volumes to be read from live prod) |
| `context_panel` | adaptive "context slot": persistent left panel on desktop (≥840px) + unified bottom sheets on mobile, one nearby→stop→vehicle state machine (client) | ON | ON | 2026-07-18 | fresh, enabled in prod 2026-07-19 (killswitch = today's independent sheets) |
| `analytics_sweep` | worker runs the citywide "sentinel sweep": slow Cron rotation over ~160 mid-route stops through the existing SWR/arrivals path, so history covers every line — not just the stops users open (backend) | OFF | ON | 2026-07-20 | permanent (gate + killswitch + auto circuit-breaker) — dormant on prod until a tempo is chosen |
| `jam_detection_collect` | worker records the per-vehicle last-fix table (`vehicle_fixes`) opportunistically on the existing SWR refreshes — no extra source calls (backend) | ON | ON | 2026-07-20 | permanent (control) — ON early so history accrues before the UI ships (Variant B needs pre-accumulated history); split from `_show` like `analytics_collect`/`analytics_show` |
| `jam_detection_show` | reveals the tram-jam UI: worker serves `/api/v1/jams`; client draws the red stalled segment, downstream-stop delay banners, bus-substitution notice (client + backend) | OFF | ON | 2026-07-20 | in-dev (UI killswitch) — OFF: client never calls `/jams`, `/jams` returns empty; recording (gated by `jam_detection_collect`) is unaffected. Enable after the first live jam + threshold calibration |

Config parameters (KV, not boolean flags):

| key | controls | prod | staging | default |
|---|---|---|---|---|
| `config:nearby_schedule_stops` | how many nearest "Nearby" stops inherit the schedule fallback (CPU cap) | 5 | 5 (default) | 5 (clamp 0..8) |
| `config:sweep_interval_day_seconds` | daytime sentinel-sweep spacing; `round(60/interval)` stops per cron tick. The **only** knob facing the source — raise it slowly (start 20, target 11) | unset→20 | unset→20 | 20 (0 = paused) |
| `config:sweep_interval_night_seconds` | night (01:00–05:00 Belgrade) sentinel-sweep spacing; **0 = paused** so the daily request profile looks human | unset→0 | unset→0 | 0 (paused) |
| `jam:sim` | **staging only** — force a synthetic tram jam on the given line number so a stand shows the red segment + banner without a live jam (also as `?sim=<line>`). Ignored in prod. | (unset) | set to a tram line to demo | unset |
| `config:jam_t_cluster` | freeze seconds before ≥2 same-direction trams on an adjacent segment count as a jam (cascading T_jam) | 180 | 180 | 180 (clamp 60..1800) |
| `config:jam_t_substitute` | relaxed freeze seconds when a substitute bus corroborates the line (halves the cluster threshold) | 90 | 90 | 90 (clamp 30..1800) |
| `config:jam_t_single` | freeze seconds for a lone vehicle (anchor only — a single vehicle is never surfaced as a jam) | 300 | 300 | 300 (clamp 60..1800) |
| `config:jam_cluster_min` | minimum vehicles for a jam cluster — **keep at 2** (3 would miss real jams on short/sparse lines) | 2 | 2 | 2 (clamp 2..5) |
| `config:jam_downstream_horizon_s` | how far past the jam's front the delay banner reaches, in **seconds of travel** (converted to a stop count via the line's mean segment time) — not a fixed stop count | 600 | 600 | 600 (clamp 120..3600) |

Sweep bookkeeping keys (not knobs — the worker owns them): `sweep:cursor`
(rotation index), `sweep:visits` (per-stop last sweep visit, for the adaptive
skip), `sweep:breaker` (consecutive-failure count; the circuit-breaker flips
`analytics_sweep` OFF at 5). If any of these can't be **read**, the sweep stands
down for that tick rather than running on defaults.

Notes: the two analytics flags are independent on purpose — turn **collect** on
early to accumulate history while **show** stays off. `nearby_sort_board` only
matters when `nearby_list` is on. `product_analytics` is a **different** system
from `analytics_collect`: the latter logs *transport* observations (arrivals →
`raw_observations`), the former logs *anonymous product-usage* events (taps →
`product_events`). `product_analytics` gates **both** ends — with it off the
client sends zero `/api/v1/events` requests **and** the worker writes nothing.

### `vehicles_on_demand` — a two-level flag (gate + killswitch)

Unlike the rollout flags above, this one doesn't retire once the feature is
stable: on-demand is the **new default**, and the aquarium stays as a user
option, so the flag permanently gates the **map's vehicle-mode toggle** that
offers the choice. (There is deliberately **no Settings item** — the toggle on
the map is the single control.) The flag is **not** the mode itself; the mode is
resolved in `app/lib/core/vehicle_map_mode.dart`:

| flag | user's stored choice | map mode |
|---|---|---|
| **OFF** | anything (or none) | **aquarium** — and the toggle is hidden |
| ON | none (default) | on-demand |
| ON | "All transport" | aquarium |
| ON | "On demand" | on-demand |

So **OFF is the killswitch**: one KV write hides the toggle and returns every
client to today's production behaviour, no matter what any user has stored. **ON**
shows the toggle on the map, defaulting to *On demand*; the user's pick wins over
the default, persists locally across restarts, and applies on the fly (no
restart). Turning the flag ON is also what drops the main load on the worker —
the aquarium's `/vehicles/nearby` fan-out becomes opt-in.

### Registry maintenance

- **New flag** → add it to `featureFlags.ts` **and** a row here (gates / prod /
  staging / date / status) in the same change.
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
