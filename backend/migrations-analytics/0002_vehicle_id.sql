-- Normalised vehicle id: the garage number when it identifies a real vehicle,
-- else NULL. The source emits placeholder ids P1..P999 (recycled across
-- vehicles) — we keep them in raw `garage_no` for the record, but they must
-- never take part in per-vehicle reasoning (dedup, speed, headways, per-vehicle
-- aggregates). Storing the decision once here keeps every downstream query
-- honest without repeating the rule.
ALTER TABLE raw_observations ADD COLUMN vehicle_id TEXT;

-- Backfill existing rows: P + integer < 1000 is junk → NULL; everything else
-- (real P##### ids) keeps its garage number as the vehicle id.
UPDATE raw_observations
SET vehicle_id = CASE
  WHEN garage_no GLOB 'P[0-9]*' AND CAST(substr(garage_no, 2) AS INTEGER) < 1000 THEN NULL
  ELSE garage_no
END;

CREATE INDEX idx_raw_vehicle ON raw_observations(vehicle_id, line, observed_at);
