import type { Env } from "../env";
import type { ArrivalDto, ArrivalsResponse } from "../types";
import { getWithStaleWhileRevalidate, type WaitUntilCtx } from "./swrCache";
import { BgnaplataTransitProvider, type RawArrival } from "./transitProvider";
import { getStopById, getLineByNumber } from "./gtfsData";

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
    () => provider.fetchArrivals(stopId),
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
