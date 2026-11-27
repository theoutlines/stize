import type { Hono } from "hono";
import type { Env } from "../env";

// The Worker's Hono app, as every routes/* module registers onto it.
export type App = Hono<{ Bindings: Env }>;
