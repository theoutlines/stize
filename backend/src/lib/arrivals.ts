import type { Env } from "../env";
import type { ArrivalDto, ArrivalsResponse } from "../types";
import { getWithStaleWhileRevalidate, type WaitUntilCtx } from "./swrCache";
import { BgnaplataTransitProvider, type RawArrival } from "./transitProvider";
import { getStopById, getLineByNumber, getLineDirections, nearestStop } from "./gtfsData";
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
    const { destination, directionId } = await resolveDirection(env, lineNumber, raw.terminus);
    arrivals.push({
      line: lineNumber,
      vehicle_type: lineMeta?.vehicle_type ?? "bus",
      eta_minutes: Math.round(raw.etaSeconds / 60),
      stops_remaining: raw.stopsRemaining,
      route_id: lineMeta?.route_id ?? raw.lineNumber,
      gps: raw.gps,
      garage_no: raw.garageNo,
      heading: raw.heading,
      destination,
      direction_id: directionId,
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

// Turn a vehicle's route terminus (a bare coordinate from the live feed) into a
// travel direction: the nearest GTFS stop's name, plus a best-effort GTFS
// direction_id when that name matches one of the line's known directions. Null
// when the arrival carried no route geometry.
async function resolveDirection(
  env: Env,
  line: string,
  terminus: { lat: number; lon: number } | null,
): Promise<{ destination: string | null; directionId: string | null }> {
  if (!terminus) return { destination: null, directionId: null };
  const stop = await nearestStop(env, terminus);
  const destination = stop?.name ?? null;
  if (!destination) return { destination: null, directionId: null };

  const directions = await getLineDirections(env, line);
  const norm = (s: string) => s.trim().toLowerCase();
  const match = directions.find((d) => norm(d.destination) === norm(destination));
  return { destination, directionId: match?.direction_id ?? null };
}
