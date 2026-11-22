// Shared request errors, mapped to HTTP status codes by the route handlers:
// ValidationError -> 400, RateLimitedError -> 429.
export class RateLimitedError extends Error {}
export class ValidationError extends Error {}

/** Constant-time admin token check: SHA-256 both sides, then timingSafeEqual. */
export async function adminTokenOk(given: string | undefined, expected: string | undefined): Promise<boolean> {
  if (!given || !expected) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(given)),
    crypto.subtle.digest("SHA-256", enc.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}
