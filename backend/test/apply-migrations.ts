import { applyD1Migrations, env } from "cloudflare:test";

await applyD1Migrations(env.STIGLA_IDEAS_DB, env.TEST_MIGRATIONS);
await applyD1Migrations(env.STIGLA_ANALYTICS_DB, env.TEST_MIGRATIONS_ANALYTICS);
