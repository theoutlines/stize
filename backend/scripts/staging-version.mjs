#!/usr/bin/env node
// Uploads a *preview version* of the staging worker (stigla-backend-staging)
// without changing which version serves live staging traffic, then prints the
// version's preview URL on its own line so a follow-up frontend build can
// capture it (see docs/staging.md).
//
//   npm run staging:version
//   → ... wrangler output ...
//   → PREVIEW_URL=https://<prefix>-stigla-backend-staging.theoutlines.workers.dev
//
// To feed it straight into a Flutter web build:
//   URL=$(npm run --silent staging:version | sed -n 's/^PREVIEW_URL=//p')
//
// Requires Preview URLs to be enabled on the worker (Cloudflare dashboard →
// the worker → Settings → Domains & Routes → Preview URLs). If they're off,
// wrangler prints no preview URL and this script exits non-zero.
import { spawnSync } from "node:child_process";

const args = ["wrangler", "versions", "upload", "--env", "staging", ...process.argv.slice(2)];

// Inherit stderr (progress/spinner) live; capture stdout so we can parse the URL
// while still echoing it verbatim.
const res = spawnSync("npx", args, {
  encoding: "utf8",
  stdio: ["inherit", "pipe", "inherit"],
});

const stdout = res.stdout ?? "";
process.stdout.write(stdout);

if (res.status !== 0) {
  process.exit(res.status ?? 1);
}

// wrangler prints e.g. "Version Preview URL: https://<prefix>-<worker>.<sub>.workers.dev"
const match = stdout.match(/Version Preview URL:\s*(https:\/\/\S+)/i);
if (!match) {
  console.error(
    "\nstaging:version — no preview URL in wrangler output.\n" +
      "Preview URLs are likely disabled on stigla-backend-staging. Enable them in\n" +
      "the Cloudflare dashboard (worker → Settings → Domains & Routes → Preview URLs),\n" +
      "then re-run. See docs/staging.md.",
  );
  process.exit(1);
}

// Machine-graspable final line for the next step to pick up.
console.log(`\nPREVIEW_URL=${match[1]}`);
