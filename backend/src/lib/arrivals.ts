import type { Env } from "../env";
import type { ArrivalDto, ArrivalsResponse } from "../types";
import { getWithStaleWhileRevalidate, type WaitUntilCtx } from "./swrCache";
import { BgnaplataTransitProvider, type RawArrival } from "./transitProvider";
import { getStopById, getLineByNumber } from "./gtfsData";
import { logObservations } from "./analytics";

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

  const arrivals: ArrivalDto[] = [];
  for (const raw of rawArrivals) {
    const lineMeta = await getLineByNumber(env, raw.lineNumber);
    arrivals.push({
      line: raw.lineNumber,
      vehicle_type: lineMeta?.vehicle_type ?? "bus",
      eta_minutes: Math.round(raw.etaSeconds / 60),
      stops_remaining: raw.stopsRemaining,
      route_id: lineMeta?.route_id ?? raw.lineNumber,
      gps: raw.gps,
      garage_no: raw.garageNo,
      heading: raw.heading,
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
