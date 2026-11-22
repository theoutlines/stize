-- upstream_events was replaced by the upstream_meter ring (migration 0009) and is
-- no longer read or written. DROP TABLE costs 0 rows written; its index goes too.
-- (agg_line_time, the v1 aggregate, was already gone on prod.)
DROP TABLE IF EXISTS upstream_events;
DROP TABLE IF EXISTS agg_line_time;
