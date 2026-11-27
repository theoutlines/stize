import type { Env } from "../../env";
import { setFlag } from "../featureFlags";

import { BREAKER_THRESHOLD, STATE_BREAKER, STATE_CURSOR, STATE_LAST_TRIP, type Breaker, type LastTrip } from "./config";

// --- D1 sweep_state accessors (see migration 0007). One tiny key/value row per
// state key; per-tick reads/writes are trivially cheap on D1's write budget. ---
export async function readSweepState(env: Env, key: string): Promise<string | null> {
  const row = await env.STIGLA_ANALYTICS_DB.prepare(
    "SELECT value FROM sweep_state WHERE key = ?",
  )
    .bind(key)
    .first<{ value: string }>();
  return row?.value ?? null;
}

export async function writeSweepState(env: Env, key: string, value: string): Promise<void> {
  await env.STIGLA_ANALYTICS_DB.prepare(
    `INSERT INTO sweep_state (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  )
    .bind(key, value, Math.floor(Date.now() / 1000))
    .run();
}

export async function persistState(
  env: Env,
  nextCursor: number,
  failures: number,
  attempted: number,
): Promise<void> {
  await writeSweepState(env, STATE_CURSOR, String(nextCursor));
  await updateBreaker(env, failures, attempted);
}

/**
 * Circuit-breaker. A tick that attempted fetches and got ONLY failures counts
 * as a consecutive failure; any success resets the counter. On reaching the
 * threshold the breaker flips `analytics_sweep` OFF (no redeploy) so the sweep
 * stops itself, and logs a signal for the report channel. A tick that fetched
 * nothing (all skipped) leaves the counter untouched.
 */
export async function updateBreaker(env: Env, failures: number, attempted: number): Promise<void> {
  if (attempted === 0) return;
  let breaker: Breaker;
  try {
    const raw = await readSweepState(env, STATE_BREAKER);
    breaker = raw ? (JSON.parse(raw) as Breaker) : { consecutiveFailures: 0, trippedAt: null };
  } catch {
    breaker = { consecutiveFailures: 0, trippedAt: null };
  }

  const allFailed = failures >= attempted;
  if (!allFailed) {
    if (breaker.consecutiveFailures !== 0) {
      await writeSweepState(env, STATE_BREAKER, JSON.stringify({ consecutiveFailures: 0, trippedAt: null }));
    }
    return;
  }

  breaker.consecutiveFailures += 1;
  if (breaker.consecutiveFailures >= BREAKER_THRESHOLD) {
    breaker.trippedAt = Math.floor(Date.now() / 1000);
    await setFlag(env, "analytics_sweep", false);
    await recordTrip(env, {
      at: breaker.trippedAt,
      kind: "failures",
      reason: `${breaker.consecutiveFailures} consecutive failed sweeps`,
    });
    // Loud, machine-greppable signal for the report channel / tail.
    console.error(
      `SWEEP_CIRCUIT_BREAKER_TRIPPED: ${breaker.consecutiveFailures} consecutive failed sweeps; ` +
        `analytics_sweep flipped OFF. Source likely challenging/down — investigate before re-enabling.`,
    );
  }
  await writeSweepState(env, STATE_BREAKER, JSON.stringify(breaker));
}

export async function recordTrip(env: Env, trip: LastTrip): Promise<void> {
  try {
    await writeSweepState(env, STATE_LAST_TRIP, JSON.stringify(trip));
  } catch (e) {
    console.error("sweep: could not record the breaker trip", e);
  }
}
