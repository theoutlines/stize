# Feature flags & releasing dormant features

Stiže ships large features into `main` **before they're finished**, kept
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
| `vehicles_on_demand` | the map's vehicle-mode toggle — the user's choice between on-demand vehicles (in context only) and the background "aquarium" (client) | ON | ON | 2026-07-15 | permanent (toggle gate + killswitch) — two-level, see below; enabled in prod 2026-07-17 with the vehicle-mode toggle |
| `product_analytics` | anonymous product-usage events: client batches them to `POST /api/v1/events`, worker writes to `product_events` (client + backend) | ON | ON | 2026-07-18 | permanent (gate + killswitch) — enabled in prod 2026-07-19 (after `hour_bucket` privacy fix; volumes to be read from live prod) |
| `context_panel` | adaptive "context slot": persistent left panel on desktop (≥840px) + unified bottom sheets on mobile, one nearby→stop→vehicle state machine (client) | ON | ON | 2026-07-18 | fresh, enabled in prod 2026-07-19 (killswitch = today's independent sheets) |
| `feedback_form` | drawer footer's in-app feedback form + `POST /api/v1/feedback` (client + backend). OFF hides the "Write to me" form action AND the endpoint refuses with 403 — full killswitch. Entry point moved 2026-07-24: the "Share feedback" footer list item (was the creator banner, now given to the donate CTA) opens the same actions sheet | **ON** | ON | 2026-07-20 | gate + killswitch — **enabled in prod 2026-07-24** with the drawer-donate release (worker 96714793). Prod stays store-only (no `GITHUB_FEEDBACK_TOKEN`): feedback lands in D1 only, no GitHub issue |
| `analytics_sweep` | worker runs the citywide "sentinel sweep": slow Cron rotation over ~160 mid-route stops through the existing SWR/arrivals path, so history covers every line — not just the stops users open (backend) | **OFF** | ON | 2026-07-20 | permanent (gate + killswitch + auto circuit-breaker) — **shuttered OFF in prod 2026-07-21** after the 20s tempo pushed combined upstream load past the source's tolerance. Safe return prepared on `feature/sweep-rate-guard`: reduced tempo (day **60s** / night paused), request budget + degradation breaker behind `upstream_budget`. Re-enable is a manual, staged step (see the report's checklist) |
| `upstream_budget` | worker meters every actual upstream fetch (live + sweep, D1 `upstream_events`) and enforces a shared rolling-hour request budget + a degradation breaker on top; OFF = fully dormant (live path unchanged), ON = metering + budget gate for the sweep (live never throttled) + auto-OFF of `analytics_sweep` on source degradation (backend) | OFF | ON | 2026-07-21 | permanent (control + guard) — turn ON FIRST (sweep still off) to measure the live baseline via `/admin/sweep/status`, set the ceiling, then re-enable the sweep |
| `jam_detection_collect` | worker records the per-vehicle last-fix table (`vehicle_fixes`) opportunistically on the existing SWR refreshes — no extra source calls (backend) | ON | ON | 2026-07-20 | permanent (control) — ON early so history accrues before the UI ships (Variant B needs pre-accumulated history); split from `_show` like `analytics_collect`/`analytics_show` |
| `jam_detection_show` | reveals the tram-jam UI: worker serves `/api/v1/jams`; client draws the red stalled segment, downstream-stop delay banners, bus-substitution notice (client + backend) | OFF | ON | 2026-07-20 | in-dev (UI killswitch) — OFF: client never calls `/jams`, `/jams` returns empty; recording (gated by `jam_detection_collect`) is unaffected. Enable after the first live jam + threshold calibration |

Config parameters (KV, not boolean flags):

| key | controls | prod | staging | default |
|---|---|---|---|---|
| `config:nearby_schedule_stops` | how many nearest "Nearby" stops inherit the schedule fallback (CPU cap) | 5 | 5 (default) | 5 (clamp 0..8) |
| `config:donate_url` | the drawer footer's **support banner** (2026-07-24: was a separate "Donate" list item). Empty/unset ⇒ the banner is hidden and the footer starts at "Share feedback"; set a URL ⇒ the banner appears (creator photo + "Support Stiže ♥" headline over a dimmed subline) and tapping it opens that URL externally. Served to the client via `/api/v1/config`'s `config` map. No boolean flag — presence of a non-empty value is the switch | `github.com/sponsors/theoutlines` (set 2026-07-24) | `github.com/sponsors/theoutlines` | _(unset ⇒ hidden)_ |
| `config:sweep_interval_day_seconds` | daytime sentinel-sweep spacing; `round(60/interval)` stops per cron tick. A knob facing the source — raise it slowly. **Reduced-tempo default is now 60s** (was 20s) after the 2026-07-21 shutter | unset→60 | unset→60 | 60 (0 = paused) |
| `config:sweep_interval_night_seconds` | night (01:00–05:00 Belgrade) sentinel-sweep spacing; **0 = paused** so the daily request profile stays even and gentle | unset→0 | unset→0 | 0 (paused) |
| `config:sweep_jitter_seconds` | randomized pre-fetch delay per cron tick, drawn uniform in `[0, 2×jitter]` (mean = jitter), so upstream hits don't land on a fixed minute phase | unset→10 | unset→10 | 10 (0 = no jitter) |
| `config:upstream_budget_hourly` | shared rolling-hour upstream request ceiling (live + sweep). The sweep stands down when its batch would cross `(ceiling − live reserve)`; **live is never gated**. Meter must be ON (`upstream_budget`). Starting value — confirm from the live baseline in `/admin/sweep/status` | unset→1200 | unset→1200 | 1200 |
| `config:upstream_live_reserve_hourly` | headroom reserved for live under the ceiling; the sweep must always leave this free | unset→300 | unset→300 | 300 |
| `config:breaker_latency_p95_ms` | degradation breaker: p95 upstream latency over the window above this trips the breaker (auto-OFF `analytics_sweep`) | unset→3000 | unset→3000 | 3000 |
| `config:breaker_non_json_fraction` | degradation breaker: share (0..1) of non-JSON/empty responses over the window above this trips the breaker | unset→0.3 | unset→0.3 | 0.3 |
| `config:breaker_window_seconds` | rolling window the breaker's p95 / non-JSON share are computed over | unset→300 | unset→300 | 300 |
| `config:breaker_min_samples` | minimum upstream samples in the window before the breaker may trip (noise guard) | unset→20 | unset→20 | 20 |
| `jam:sim` | **staging only** — force a synthetic tram jam on the given line number so a stand shows the red segment + banner without a live jam (also as `?sim=<line>`). Ignored in prod. | (unset) | set to a tram line to demo | unset |
| `config:jam_t_cluster` | freeze seconds before ≥2 same-direction trams on an adjacent segment count as a jam (cascading T_jam) | 180 | 180 | 180 (clamp 60..1800) |
| `config:jam_t_substitute` | relaxed freeze seconds when a substitute bus corroborates the line (halves the cluster threshold) | 90 | 90 | 90 (clamp 30..1800) |
| `config:jam_t_single` | freeze seconds for a lone vehicle (anchor only — a single vehicle is never surfaced as a jam) | 300 | 300 | 300 (clamp 60..1800) |
| `config:jam_cluster_min` | minimum vehicles for a jam cluster — **keep at 2** (3 would miss real jams on short/sparse lines) | 2 | 2 | 2 (clamp 2..5) |
| `config:jam_downstream_horizon_s` | how far past the jam's front the delay banner reaches, in **seconds of travel** (converted to a stop count via the line's mean segment time) — not a fixed stop count | 600 | 600 | 600 (clamp 120..3600) |

Sweep bookkeeping state (not knobs — the worker owns it) lives in **D1**, not
KV: table `sweep_state` in `stigla-analytics` (migration `0007_sweep_state.sql`),
one key/value row per item — `cursor` (rotation index) and `breaker`
(consecutive-failure count; the circuit-breaker flips `analytics_sweep` OFF at
5). If this state can't be **read**, the sweep stands down for that tick rather
than running on defaults. There is no `visits` state anymore — the adaptive skip
derives "organic traffic refreshed this sentinel within the current cycle" from
`MAX(observed_at)` in `raw_observations` (see `SKIP_MARGIN_SECONDS` in
`lib/sweep.ts`).

The request meter (behind `upstream_budget`) writes one row per **actual** upstream
fetch to D1 `upstream_events` (`stigla-analytics`, migration `0008`), never on a
cache hit and never in KV — same KV-vs-D1 principle. It backs the rolling-hour
budget, the degradation breaker (p95 latency + non-JSON share), and the
`/api/v1/admin/sweep/status` read-out; rows are pruned to a ~2h retention.

> **Principle — KV vs D1.** KV holds **human-flipped knobs and flags** only
> (`flag:*`, `config:*`): tiny, rarely written, read-mostly. **Machine state
> written on a minute cadence goes in D1**, never KV. Reason: KV's free tier is
> **1000 writes/day**; the sweep persisting `cursor` (+ the old `visits`) every
> cron tick was ~2400 writes/day and tripped Cloudflare's "50% daily KV
> operation limit" alert on 2026-07-21. D1's write budget (~100k/day) absorbs
> per-minute writes trivially, and the sweep already writes `raw_observations`
> there. When adding automation, ask "how often is this written?" — anything
> per-tick belongs in D1.

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
  curl -X POST https://api.stize.app/api/v1/admin/flags \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -d '{"flag":"analytics_collect","value":true}'

  # reveal the screens LATER, when ready
  curl -X POST https://api.stize.app/api/v1/admin/flags \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -d '{"flag":"analytics_show","value":true}'
  ```
- `GET /api/v1/admin/sweep/status` (header `X-Admin-Token: $ADMIN_TOKEN`): current
  upstream req/hr (live vs sweep), remaining sweep budget, and degradation-breaker
  health — so the sweep's pacing/guard can be checked without `wrangler tail`.
  Returns counts/config only, never secrets.

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
