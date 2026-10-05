-- D1 write budget (incident 2026-10-05, docs/reports/2026-10-05-d1-write-budget.md).
--
-- The account lives on the D1 free tier permanently: 100k rows_written/day,
-- account-wide. D1 counts every index entry a write touches as a written row, so a
-- raw_observations INSERT cost 5 rows per arrival (table + 4 indexes). Measured:
-- ~135 rows_written per upstream fetch, i.e. ~2 hours of one open map exhausted the
-- day. This migration only removes write amplification; storage is not scarce.
-- (Measured in miniflare, which matches prod accounting: DROP INDEX costs 0 rows.)

-- 1. raw_observations: every read path filters by an `observed_at` range (aggregate
--    windows, per-vehicle and sched_delay passes), so only idx_raw_time is used.
--    These three match no WHERE and no window PARTITION BY — pure write cost.
DROP INDEX IF EXISTS idx_raw_veh;
DROP INDEX IF EXISTS idx_raw_stop;
DROP INDEX IF EXISTS idx_raw_vehicle;

-- 2. Last time each stop's live board was observed — the lookup the sweep's
--    adaptive skip needs ("did organic traffic refresh this sentinel within the
--    cycle?"). Previously a `stop_id IN (...)` scan over ALL raw (no usable index:
--    ~540k rows_read per tick). An index on raw(stop_id, observed_at) would cost +1
--    written row per ARRIVAL (~20 per fetch); this one-row-per-stop table costs +1
--    per FETCH and the skip reads exactly one row per sentinel. WITHOUT ROWID +
--    PK-only, so an upsert writes exactly 1 row. Bounded by the number of stops.
CREATE TABLE IF NOT EXISTS stop_last_observed (
  stop_id TEXT PRIMARY KEY,
  observed_at INTEGER NOT NULL   -- unix seconds of the latest logged board
) WITHOUT ROWID;

-- 3. Upstream request meter as a fixed-size ring of per-minute buckets, replacing
--    the per-fetch `upstream_events` log (3 rows written per fetch + a per-row DELETE
--    prune that only ran from the sweep tick — with the sweep OFF it never ran and
--    the table grew without bound). One row per (minute slot, kind); a fetch
--    upserts its bucket in place (1 row written), and a slot whose stored `minute`
--    is stale is reset on the next write — bounded with no DELETE at all.
--    Latency is kept as a histogram (lb0..lb12, upper edges in ms:
--    250,500,750,1000,1500,2000,2500,3000,4000,5000,7500,10000,+inf) so the
--    degradation breaker's p95 still works; it is exact whenever the configured
--    threshold is one of the edges (the 3000 ms default is).
--    `upstream_events` is left in place (frozen, no longer written): dropping it
--    buys nothing on a storage-unconstrained DB.
CREATE TABLE IF NOT EXISTS upstream_meter (
  slot INTEGER NOT NULL,      -- unix minute mod ring size
  kind TEXT NOT NULL,         -- 'live' | 'sweep'
  minute INTEGER NOT NULL,    -- the unix minute (ts / 60) this slot currently holds
  n INTEGER NOT NULL DEFAULT 0,
  non_json INTEGER NOT NULL DEFAULT 0,  -- outcome != 'json'
  lb0 INTEGER NOT NULL DEFAULT 0,
  lb1 INTEGER NOT NULL DEFAULT 0,
  lb2 INTEGER NOT NULL DEFAULT 0,
  lb3 INTEGER NOT NULL DEFAULT 0,
  lb4 INTEGER NOT NULL DEFAULT 0,
  lb5 INTEGER NOT NULL DEFAULT 0,
  lb6 INTEGER NOT NULL DEFAULT 0,
  lb7 INTEGER NOT NULL DEFAULT 0,
  lb8 INTEGER NOT NULL DEFAULT 0,
  lb9 INTEGER NOT NULL DEFAULT 0,
  lb10 INTEGER NOT NULL DEFAULT 0,
  lb11 INTEGER NOT NULL DEFAULT 0,
  lb12 INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (slot, kind)
) WITHOUT ROWID;
