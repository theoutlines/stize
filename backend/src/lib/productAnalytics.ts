import type { Env } from "../env";
import { getFlagMemoized } from "./featureFlags";
import { chunkedInsert } from "./analytics";
import type { WaitUntilCtx } from "./swrCache";

// Product analytics — our own contour (worker -> analytics D1), never an external
// vendor. Anonymous by design: an event is a name + enum-only properties + an
// hour-coarsened timestamp. No user-id, no IP, no coordinates, no free text. The
// only linkage is an ephemeral in-tab `session` (random, not persisted on the
// client, not an identity) so funnels like stop_open -> vehicle_follow can be
// read. See migrations-analytics/0004_product_events.sql and the README privacy
// note. Adding an event or a property means editing THIS allow-list — anything
// not listed here is dropped on the way in and never reaches the table.

// event name -> { propKey -> allowed enum values }. An empty object means the
// event carries no properties (any props sent with it are dropped).
export const PRODUCT_EVENT_SCHEMA = {
  // DAU counter + mode distribution + local-vs-tourist cohort. `locale_class` is
  // the CLASS of the system locale (sr/ru/en/other), never the exact locale.
  app_open: {
    mode: ["on_demand", "aquarium"],
    locale_class: ["sr", "ru", "en", "other"],
  },
  // Is the on-demand default accepted, or do people switch back to the aquarium?
  mode_toggle: { to: ["on_demand", "aquarium"] },
  // The main entry into the product, tagged by how the stop was reached.
  stop_open: { source: ["pin", "nearby", "favorites", "search"] },
  // Is "follow" — a core feature — actually used, and from where?
  vehicle_follow: { source: ["sheet", "nearby", "marker"] },
  // Do people want the Fleet-ID comfort sort (pillar check)?
  sort_comfort: {},
  // Is the line filter used?
  line_filter: {},
  // What role does search play?
  search_used: {},
  // Is favouriting alive?
  favorite_add: {},
  favorite_remove: {},
} as const satisfies Record<string, Record<string, readonly string[]>>;

export type ProductEventName = keyof typeof PRODUCT_EVENT_SCHEMA;

export function isProductEvent(name: string): name is ProductEventName {
  return Object.prototype.hasOwnProperty.call(PRODUCT_EVENT_SCHEMA, name);
}

// Hard caps so a single request can't blow the worker budget or store junk. A
// batch over the cap is truncated (excess dropped), not rejected — analytics is
// fire-and-forget and must never surface an error to the client.
export const MAX_BATCH = 100;
// Ephemeral session id shape: a short random token, nothing that could carry an
// identity or free text. Anything outside this is dropped to NULL.
const SESSION_RE = /^[A-Za-z0-9_-]{1,32}$/;

const PRODUCT_EVENT_COLUMNS = ["event", "props", "session", "hour_bucket"] as const;

export interface CleanEvent {
  event: ProductEventName;
  props: Record<string, string> | null;
  session: string | null;
}

/**
 * Validate one raw event against the allow-list. Returns null when the event
 * name is unknown (dropped). Unknown property keys and out-of-enum values are
 * silently stripped, so a client that sends an extra or malformed property never
 * pollutes the table — only allow-listed enum values survive.
 */
export function sanitizeEvent(raw: unknown): CleanEvent | null {
  if (typeof raw !== "object" || raw === null) return null;
  const obj = raw as Record<string, unknown>;
  const name = obj.event;
  if (typeof name !== "string" || !isProductEvent(name)) return null;

  const allowed = PRODUCT_EVENT_SCHEMA[name] as Record<string, readonly string[]>;
  let props: Record<string, string> | null = null;
  const rawProps = obj.props;
  if (typeof rawProps === "object" && rawProps !== null) {
    for (const [key, values] of Object.entries(allowed)) {
      const v = (rawProps as Record<string, unknown>)[key];
      if (typeof v === "string" && values.includes(v)) {
        (props ??= {})[key] = v;
      }
    }
  }

  const session = typeof obj.session === "string" && SESSION_RE.test(obj.session) ? obj.session : null;
  return { event: name, props, session };
}

/**
 * Sanitize a raw batch: cap its size, drop unknown events, strip unknown props.
 * Pure (no I/O) so the request handler can compute the accepted count for its
 * response before handing the write off to `waitUntil`.
 */
export function sanitizeBatch(rawEvents: unknown): CleanEvent[] {
  if (!Array.isArray(rawEvents)) return [];
  const clean: CleanEvent[] = [];
  for (const raw of rawEvents.slice(0, MAX_BATCH)) {
    const e = sanitizeEvent(raw);
    if (e) clean.push(e);
  }
  return clean;
}

/**
 * Write a sanitized batch of product events into `product_events`.
 *
 * Flag-gated (`product_analytics`) and meant to be called from `ctx.waitUntil`
 * so it adds ZERO latency to the response and can never fail the request. The
 * timestamp is coarsened to the hour and stamped SERVER-side on receipt — the
 * client never sends a time, so there's nothing clock-based to correlate on.
 * Inserts go through the shared `chunkedInsert` (D1 bound-param cap), so this
 * path can't reintroduce the "too many SQL variables" bug.
 */
export async function logProductEvents(
  env: Env,
  ctx: WaitUntilCtx,
  events: readonly CleanEvent[],
): Promise<void> {
  if (events.length === 0) return;
  if (!(await getFlagMemoized(env, ctx, "product_analytics"))) return;

  const hourBucket = Math.floor(Date.now() / 3600) * 3600;
  const rows = events.map((e) => [
    e.event,
    e.props ? JSON.stringify(e.props) : null,
    e.session,
    hourBucket,
  ]);
  await chunkedInsert(env.STIGLA_ANALYTICS_DB, "product_events", PRODUCT_EVENT_COLUMNS, rows);
}
