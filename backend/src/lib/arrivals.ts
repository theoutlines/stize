import type { Env } from "../env";
import type { ArrivalDto, ArrivalsResponse } from "../types";
import { getWithStaleWhileRevalidate, type WaitUntilCtx } from "./swrCache";
import { BgnaplataTransitProvider, type RawArrival } from "./transitProvider";
import { getStopById, getLineByNumber } from "./gtfsData";
import { logObservations } from "./analytics";
import { getFlag } from "./featureFlags";

const ARRIVALS_TTL_SECONDS = 30;

export async function getArrivals(
  env: Env,
  ctx: WaitUntilCtx,
  stopId: string,
): Promise<ArrivalsResponse | null> {
  const stop = await getStopById(env, stopId);
  if (!stop) return null;

  const provider = new BgnaplataTransitProvider(env);
  const cacheKeyUrl = `https://cache.stigla.internal/arrivals/${encodeURIComponent(stopId)}`;

  const { data: rawArrivals, updatedAt } = await getWithStaleWhileRevalidate<RawArrival[]>(
    cacheKeyUrl,
    ARRIVALS_TTL_SECONDS,
    ctx,
    // Wrap the fresh upstream fetch so analytics logs exactly what we just
    // pulled — this runs only on a real refresh (not cache hits), so it adds no
    // extra load on the source. Fire-and-forget; never blocks the response.
    () =>
      provider.fetchArrivals(stopId).then((raw) => {
        ctx.waitUntil(
          logObservations(env, stopId, raw).catch((e) =>
            console.error("analytics log failed", e),
          ),
        );
        return raw;
      }),
  );

  // Timed-trajectory plan is additive and flag-gated: emitted only when the
  // feature is on (default ON on staging, OFF on prod), so prod payload and old
  // clients are untouched. Read once per board build.
  const timedTrajectoryOn = await getFlag(env, "timed_trajectory");

  const arrivals: ArrivalDto[] = [];
  for (const raw of rawArrivals) {
    // Upstream occasionally emits a junk row with no line number. It can't be
    // rendered (a bus icon + "Now" with no line/direction) and can't be
    // filtered client-side, so drop it at the source (F6).
    const lineNumber = raw.lineNumber?.trim();
    if (!lineNumber) {
      console.warn("dropping arrival with empty line number", {
        stopId,
        garageNo: raw.garageNo,
      });
      continue;
    }
    const lineMeta = await getLineByNumber(env, lineNumber);
    arrivals.push({
      line: lineNumber,
      vehicle_type: lineMeta?.vehicle_type ?? "bus",
      eta_minutes: Math.round(raw.etaSeconds / 60),
      stops_remaining: raw.stopsRemaining,
      route_id: lineMeta?.route_id ?? raw.lineNumber,
      gps: raw.gps,
      garage_no: raw.garageNo,
      heading: raw.heading,
      // `raw.trajectory` is undefined on a stale pre-deploy cache entry; treat
      // that the same as "no plan" so an old cache never breaks the response.
      trajectory: timedTrajectoryOn
        ? (raw.trajectory?.map((p) => ({
            lat: p.lat,
            lon: p.lon,
            eta_seconds: p.etaSeconds,
          })) ?? null)
        : undefined,
    });
  }
  arrivals.sort((a, b) => a.eta_minutes - b.eta_minutes);

  return {
    stop_id: stop.stop_id,
    stop_name: stop.name,
    updated_at: updatedAt,
    arrivals,
    service_status: "ok",
  };
}
