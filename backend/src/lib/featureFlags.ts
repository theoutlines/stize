import type { Env } from "../env";

// Feature flags live in KV — the same remote, no-redeploy mechanism as the kill
// switch (see killswitch.ts). Flipping a flag is a single KV write; every worker
// isolate reads the new value on its next request. This lets us ship dormant
// code to `main` and turn it on later without a rebuild.
//
// Two independent analytics flags (see the transport-analytics feature):
//   analytics_collect — the worker logs arrival observations to build history.
//                       Turn this on EARLY so data accumulates while the screens
//                       are still hidden.
//   analytics_show    — the app reveals the (draft) analytics screens to users.
//                       Turn this on only once the screens are ready.
//   nearby_list       — the app shows the experimental "Nearby" list (a
//                       draggable sheet over the map). Off on prod, on on
//                       staging (like every in-dev flag).
//   nearby_sort_board — the "Nearby" list is ordered by time-to-board (walk to
//                       the stop + wait for the soonest catchable departure)
//                       instead of by bare ETA. Off on prod, on on staging.
//   coverage_map_show — the app reveals the coverage-map tab (a static
//                       infographic layer). OFF on prod, ON on staging until
//                       it's ready to ship.
//   coverage_on_main_map — the app shows the coverage heatmap as a passive
//                       background on the *main* map when zoomed out (instead of
//                       stop clusters). Independent of coverage_map_show: the
//                       tab can be off while the overlay is on, and vice-versa.
//                       OFF on prod, ON on staging.
//   vehicles_on_demand — the main map stops rendering the whole "aquarium" of
//                       background vehicles. Instead vehicles appear only in
//                       context: the markers of a tapped stop's arrivals, and a
//                       followed vehicle. Purely a client-render flag — the
//                       worker is unchanged; the client simply stops calling
//                       /vehicles/nearby while there's no context, which drops
//                       the map fan-out load. OFF on prod, ON on staging.
//   product_analytics — the client emits anonymous product-usage events (batched
//                       to POST /api/v1/events; the worker writes them to the
//                       product_events table via waitUntil). Gates BOTH the
//                       client (OFF = zero analytics requests) and the worker's
//                       write. Distinct from analytics_collect (that's the
//                       TRANSPORT-observation logger). OFF on prod, ON on staging
//                       until we've checked the volume/cost, then flip prod
//                       deliberately.
//   analytics_sweep   — the worker runs the citywide "sentinel sweep": a slow
//                       Cron rotation over a small set of mid-route stops that
//                       observes the active fleet of every line, so history
//                       stops being limited to the stops users happen to open.
//                       It reuses the existing SWR/arrivals path (no new source
//                       calls) and the existing observation logger. OFF on prod
//                       (dormant until a tempo is chosen) / ON on staging — but
//                       staging ALSO reaches the source, so only enable it on
//                       staging while actively verifying. OFF is the killswitch;
//                       the circuit-breaker also flips it OFF on repeated
//                       non-JSON/error responses (see lib/sweep.ts).
//   context_panel     — the app presents the adaptive "context slot": a persistent
//                       left panel on desktop (≥840px) and unified bottom sheets on
//                       mobile, both driven by one state machine (nearby → stop →
//                       vehicle). Purely a client-render flag — the worker is
//                       unchanged; this entry only lets /config serve the flag so
//                       it can default ON on staging / OFF on prod and be flipped
//                       in KV. OFF is the killswitch (today's UI, untouched).
//   jam_detection_collect — the worker records the per-vehicle last-fix table
//                       (opportunistic, on the existing SWR refreshes — no extra
//                       source calls). Split from `jam_detection_show` on purpose,
//                       exactly like analytics_collect vs analytics_show: turn
//                       COLLECT on EARLY (incl. prod) so history accumulates before
//                       the UI ships — that is the whole point of the server-memory
//                       design ("a jam shows the instant you open the app"); if
//                       recording only started with the UI, the first users after
//                       the flip would still wait out T_jam (Variant-A behaviour).
//                       ON on prod + staging. OFF = the worker records nothing.
//   jam_detection_show — reveals the tram-jam UI: the worker serves GET
//                       /api/v1/jams and the client draws the red stalled segment,
//                       downstream-stop delay banners, and the bus-substitution
//                       notice. OFF on prod (enable after the first live jam +
//                       threshold calibration), ON on staging. OFF is the UI
//                       killswitch; with it off the client never calls /jams and
//                       /jams returns empty (recording, gated separately by
//                       jam_detection_collect, is unaffected).
export const FEATURE_FLAGS = [
  "analytics_collect",
  "analytics_show",
  "nearby_list",
  "nearby_sort_board",
  "coverage_map_show",
  "coverage_on_main_map",
  "vehicles_on_demand",
  "product_analytics",
  "context_panel",
  "analytics_sweep",
  "jam_detection_collect",
  "jam_detection_show",
] as const;
export type FeatureFlag = (typeof FEATURE_FLAGS)[number];

export function isFeatureFlag(name: string): name is FeatureFlag {
  return (FEATURE_FLAGS as readonly string[]).includes(name);
}

const kvKey = (flag: FeatureFlag) => `flag:${flag}`;

// Default value for a flag whose KV key hasn't been set. On **staging** every
// in-development flag defaults ON so the whole app can be exercised there; on
// **production** they default OFF until explicitly enabled. An explicit KV
// value always wins over this (so either env can be overridden per flag).
function defaultFor(env: Env): boolean {
  return env.ENVIRONMENT === "staging";
}

export async function getFlag(env: Env, flag: FeatureFlag): Promise<boolean> {
  const value = await env.STIGLA_KV.get(kvKey(flag));
  if (value === null) return defaultFor(env);
  return value === "1";
}

// Per-invocation flag memo. Keyed by a request-unique object (`scope` — the
// Worker's per-request ctx), so within ONE invocation a flag is read from KV
// once even across a fan-out (the map path's 18 per-stop analytics logs used to
// fire 18 identical KV reads → 18 subrequests). It is deliberately NOT a global
// or TTL cache: a fresh request gets a fresh scope, so a KV flag flip is still
// picked up on the very next request (instant-flip semantics preserved).
const invocationFlagCache = new WeakMap<object, Map<FeatureFlag, Promise<boolean>>>();
export function getFlagMemoized(env: Env, scope: object, flag: FeatureFlag): Promise<boolean> {
  let byFlag = invocationFlagCache.get(scope);
  if (!byFlag) invocationFlagCache.set(scope, (byFlag = new Map()));
  let pending = byFlag.get(flag);
  if (!pending) byFlag.set(flag, (pending = getFlag(env, flag)));
  return pending;
}

export async function setFlag(env: Env, flag: FeatureFlag, on: boolean): Promise<void> {
  await env.STIGLA_KV.put(kvKey(flag), on ? "1" : "0");
}

export async function getAllFlags(env: Env): Promise<Record<FeatureFlag, boolean>> {
  const entries = await Promise.all(
    FEATURE_FLAGS.map(async (f) => [f, await getFlag(env, f)] as const),
  );
  return Object.fromEntries(entries) as Record<FeatureFlag, boolean>;
}
