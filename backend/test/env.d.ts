import type { D1Migration } from "@cloudflare/vitest-pool-workers";
import type { Env as WorkerEnv } from "../src/env";

// vitest-pool-workers 0.2x types `cloudflare:test`'s env as `Cloudflare.Env`.
declare global {
  namespace Cloudflare {
    interface Env extends WorkerEnv {
      TEST_MIGRATIONS: D1Migration[];
      TEST_MIGRATIONS_ANALYTICS: D1Migration[];
    }
  }
}
