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
//   symbol_layer      — the app renders moving vehicles as a MapLibre GPU symbol
//                       layer (batched, sub-linear in vehicle count) instead of
//                       per-vehicle Flutter widgets. Client-side render flag.
//                       OFF on prod (widget path stays the fallback), ON staging.
//   live_position_only — the app draws on the map only vehicles with a real live
//                       GPS position. The upstream emits schedule-derived
//                       placeholder rows (junk garage id `P1..P999`, GPS = the
//                       stop's own coordinate) that aren't tracked vehicles; with
//                       this on they stay in the arrivals *list* but are not drawn
//                       as (stationary, stacked-on-the-stop) markers. Read
//                       client-side. OFF on prod, ON on staging.
//   schedule_fallback — hybrid live+schedule. Gates the arrivals *list* (Phase 1):
//                       the stop board gains planned departures
//                       (`source:"scheduled"`), deduped against live. Also the
//                       flag the *client* reads to render scheduled objects at
//                       all. OFF prod.
//   schedule_map — the map (`/vehicles/nearby`) emits schedule-predicted vehicles
//                       (Phase 2) where a line has no live vehicle, moved by the
//                       same timed trajectory. Separate from schedule_fallback so
//                       the map can be rolled back without killing the (proven)
//                       list. Both it and schedule_fallback must be ON for
//                       scheduled buses to appear on the map. OFF prod.
export const FEATURE_FLAGS = [
  "analytics_collect",
  "analytics_show",
  "nearby_list",
  "nearby_sort_board",
  "coverage_map_show",
  "coverage_on_main_map",
  "symbol_layer",
  "live_position_only",
  "schedule_fallback",
  "schedule_map",
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

export async function setFlag(env: Env, flag: FeatureFlag, on: boolean): Promise<void> {
  await env.STIGLA_KV.put(kvKey(flag), on ? "1" : "0");
}

export async function getAllFlags(env: Env): Promise<Record<FeatureFlag, boolean>> {
  const entries = await Promise.all(
    FEATURE_FLAGS.map(async (f) => [f, await getFlag(env, f)] as const),
  );
  return Object.fromEntries(entries) as Record<FeatureFlag, boolean>;
}
