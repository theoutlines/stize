// Types for the I/O-free GTFS build core (gtfs-core.mjs), so the backend TS
// test (test/gtfs-core.test.ts) can import it type-checked.

export const TYPE_ORDER: readonly ["tram", "trolleybus", "bus"];

export function deriveStopTypes(
  lines: string[],
  lineTypeByNumber: Map<string, string>,
): string[];

export interface StopCoord {
  lat: number;
  lon: number;
  [key: string]: unknown;
}

export interface StopOverride {
  op: "swap_coords" | "set_coords";
  stop_ids?: string[];
  stop_id?: string;
  lat?: number;
  lon?: number;
  reason: string;
  date: string;
  evidence: string;
}

export interface StopOverridesDoc {
  overrides: StopOverride[];
}

export function applyStopOverrides(
  stopsById: Map<string, StopCoord>,
  doc: StopOverridesDoc | null | undefined,
): { applied: number; details: string[] };

export function nearestMetersToPolylines(
  lat: number,
  lon: number,
  polylines: number[][][],
): number;

export interface TramOffender {
  stop_id: string;
  name: string;
  distM: number;
}

export function tramStopsWithoutRail(
  stops: Array<{ stop_id: string; name: string; lat: number; lon: number; types: string[] }>,
  tramPolylines: number[][][],
  thresholdM?: number,
): TramOffender[];
