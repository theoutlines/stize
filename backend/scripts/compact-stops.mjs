// Writes public/gtfs/stops.compact.json: the same stops as stops.json, stored
// column by column with lines/types joined into strings. The worker parses it
// about 6x faster than the object-per-stop file (≈0.5 ms vs ≈3 ms), which matters
// on a cold isolate under the free plan's 10 ms CPU limit per request
// (technical audit 2026-11-22, T1). stops.json stays the source of truth.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const GTFS = join(dirname(fileURLToPath(import.meta.url)), "..", "public", "gtfs");
const stops = JSON.parse(readFileSync(join(GTFS, "stops.json"), "utf-8")).stops;
const out = { stop_id: [], name: [], lat: [], lon: [], lines: [], types: [] };
for (const s of stops) {
  out.stop_id.push(s.stop_id);
  out.name.push(s.name);
  out.lat.push(s.lat);
  out.lon.push(s.lon);
  out.lines.push((s.lines ?? []).join(","));
  out.types.push((s.types ?? []).join(","));
}
writeFileSync(join(GTFS, "stops.compact.json"), JSON.stringify(out));
console.log(`stops.compact.json: ${stops.length} stops`);
