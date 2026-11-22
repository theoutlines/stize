// Compare the D1 migrations applied on a deployment with the repo's folders.
// Usage: ADMIN_TOKEN=... node scripts/check-migrations.mjs [https://api.stize.app]
import { readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const base = process.argv[2] ?? "https://api.stize.app";
const res = await fetch(`${base}/api/v1/admin/migrations`, {
  headers: { "X-Admin-Token": process.env.ADMIN_TOKEN ?? "" },
});
if (!res.ok) throw new Error(`HTTP ${res.status}`);
const applied = await res.json();
let drift = false;
for (const [db, dir] of [["ideas", "migrations"], ["analytics", "migrations-analytics"]]) {
  const files = readdirSync(join(root, dir)).filter((f) => f.endsWith(".sql")).sort();
  const got = new Set(applied[db] ?? []);
  const missing = files.filter((f) => !got.has(f));
  const extra = [...got].filter((f) => !files.includes(f));
  console.log(`${db}: ${files.length} in repo, ${got.size} applied`);
  if (missing.length) console.log(`  NOT applied: ${missing.join(", ")}`);
  if (extra.length) console.log(`  applied but not in repo: ${extra.join(", ")}`);
  drift ||= missing.length > 0 || extra.length > 0;
}
process.exit(drift ? 1 : 0);
