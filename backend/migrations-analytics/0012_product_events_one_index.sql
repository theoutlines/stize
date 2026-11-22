-- product_events is read ad hoc by time range (idx_pe_time). The second index,
-- (event, hour_bucket), cost one more written row per event for a lookup the
-- time index already serves at this table size (audit round 2, T4).
DROP INDEX IF EXISTS idx_pe_event_time;
