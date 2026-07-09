const EARTH_RADIUS_METERS = 6371000;

export function haversineDistanceMeters(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);

  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(h));
}

type LatLon = { lat: number; lon: number };

// Perpendicular distance (metres) from point p to the segment a→b, using a
// local equirectangular projection around a (accurate at city scale). Also
// reports `t`, the clamped [0,1] position of the projection along the segment.
export function distanceToSegmentMeters(p: LatLon, a: LatLon, b: LatLon): { distance: number; t: number } {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const cosLat = Math.cos(toRad(a.lat));
  const proj = (o: LatLon) => ({
    x: toRad(o.lon - a.lon) * cosLat * EARTH_RADIUS_METERS,
    y: toRad(o.lat - a.lat) * EARTH_RADIUS_METERS,
  });
  const P = proj(p);
  const B = proj(b);
  const len2 = B.x * B.x + B.y * B.y;
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, (P.x * B.x + P.y * B.y) / len2));
  const dx = P.x - t * B.x;
  const dy = P.y - t * B.y;
  return { distance: Math.sqrt(dx * dx + dy * dy), t };
}

// Initial compass bearing from a to b, in degrees (0 = north, clockwise).
export function bearingDegrees(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLon = toRad(b.lon - a.lon);
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  return (Math.atan2(y, x) * (180 / Math.PI) + 360) % 360;
}
