import type { Env } from "../../env";
import type { AnalyticsBucket, LineAnalyticsResponse } from "../../types";

// Reading a line's analytics for the app.

export interface AggRow {
  dow: number;
  hour: number;
  samples: number;
  arrivals: number;
  headway_count: number;
  headway_secs_sum: number;
  speed_count: number;
  speed_stops_per_min_sum: number;
  sched_delay_count?: number;
  sched_delay_secs_sum?: number;
}

export const emptyFold = () => ({
  samples: 0,
  arrivals: 0,
  headway_count: 0,
  headway_secs_sum: 0,
  speed_count: 0,
  speed_stops_per_min_sum: 0,
});

/**
 * Serve a line's rolled-up analytics, folded into per-hour and per-dow views.
 * Reads agg_line_dir_time and folds ACROSS directions so the response shape is
 * unchanged (the draft screens keep working) — the per-direction split and the
 * headway histogram are stored for later features, not exposed here yet.
 */
export async function getLineAnalytics(env: Env, line: string): Promise<LineAnalyticsResponse> {
  const db = env.STIGLA_ANALYTICS_DB;
  // Fold directions in SQL: sum every metric per (dow, hour) across directions.
  const { results } = await db
    .prepare(
      `SELECT dow, hour,
              SUM(samples) AS samples, SUM(arrivals) AS arrivals,
              SUM(headway_count) AS headway_count, SUM(headway_secs_sum) AS headway_secs_sum,
              SUM(speed_count) AS speed_count, SUM(speed_stops_per_min_sum) AS speed_stops_per_min_sum,
              SUM(sched_delay_count) AS sched_delay_count, SUM(sched_delay_secs_sum) AS sched_delay_secs_sum
       FROM agg_line_dir_time WHERE line = ?
       GROUP BY dow, hour`,
    )
    .bind(line)
    .all<AggRow>();

  const fold = (size: number, keyOf: (r: AggRow) => number): AnalyticsBucket[] => {
    const acc = Array.from({ length: size }, (_, key) => ({ key, ...emptyFold() }));
    for (const r of results) {
      const b = acc[keyOf(r)];
      b.samples += r.samples;
      b.arrivals += r.arrivals;
      b.headway_count += r.headway_count;
      b.headway_secs_sum += r.headway_secs_sum;
      b.speed_count += r.speed_count;
      b.speed_stops_per_min_sum += r.speed_stops_per_min_sum;
    }
    return acc.map((b) => ({
      key: b.key,
      samples: b.samples,
      arrivals: b.arrivals,
      mean_headway_secs: b.headway_count ? Math.round(b.headway_secs_sum / b.headway_count) : null,
      mean_speed_stops_per_min: b.speed_count
        ? Number((b.speed_stops_per_min_sum / b.speed_count).toFixed(3))
        : null,
    }));
  };

  const lastRun = await db
    .prepare("SELECT value FROM agg_state WHERE key = 'last_run'")
    .first<{ value: string }>();

  return {
    line,
    total_samples: results.reduce((a, r) => a + r.samples, 0),
    by_hour: fold(24, (r) => r.hour),
    by_dow: fold(7, (r) => r.dow),
    grid: results.map((r) => ({
      dow: r.dow,
      hour: r.hour,
      samples: r.samples,
      arrivals: r.arrivals,
      mean_headway_secs: r.headway_count ? Math.round(r.headway_secs_sum / r.headway_count) : null,
      mean_speed_stops_per_min: r.speed_count
        ? Number((r.speed_stops_per_min_sum / r.speed_count).toFixed(3))
        : null,
      // Signed mean delay vs the timetable (city section); null = unknown.
      delay_count: r.sched_delay_count ?? 0,
      mean_delay_secs: r.sched_delay_count ? Math.round((r.sched_delay_secs_sum ?? 0) / r.sched_delay_count) : null,
    })),
    updated_at: lastRun ? Number(lastRun.value) : null,
    punctuality: null,
  };
}
