// Shared request errors, mapped to HTTP status codes by the route handlers:
// ValidationError -> 400, RateLimitedError -> 429.
export class RateLimitedError extends Error {}
export class ValidationError extends Error {}
