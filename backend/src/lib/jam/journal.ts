import type { Env } from "../../env";
import { computeJams } from "./compute";

// journalJams: the minute cron's record of active jams.

/**
 * Record the jams the detector shows right now into `jam_journal` (one upsert per
 * active jam). Called from the minute cron every 5 minutes while
 * `jam_detection_show` is on. Returns how many jams were recorded.
 */
export async function journalJams(env: Env, now: number): Promise<number> {
  const { jams, feed_healthy } = await computeJams(env, now);
  if (!feed_healthy || jams.length === 0) return 0;
  const day = new Date(now).toISOString().slice(0, 10);
  const at = Math.floor(now / 1000);
  await env.STIGLA_ANALYTICS_DB.batch(
    jams.map((j) =>
      env.STIGLA_ANALYTICS_DB.prepare(
        `INSERT INTO jam_journal (day, line, direction_route_id, first_at, last_at, max_vehicles, max_frozen_secs, has_substitute)
         VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6, ?7)
         ON CONFLICT(day, line, direction_route_id) DO UPDATE SET
           last_at = excluded.last_at,
           max_vehicles = MAX(max_vehicles, excluded.max_vehicles),
           max_frozen_secs = MAX(max_frozen_secs, excluded.max_frozen_secs),
           has_substitute = MAX(has_substitute, excluded.has_substitute)`,
      ).bind(
        day,
        j.line,
        j.direction_route_id ?? "",
        at,
        j.vehicles.length,
        Math.round(j.frozen_secs),
        j.has_substitute ? 1 : 0,
      ),
    ),
  );
  return jams.length;
}
