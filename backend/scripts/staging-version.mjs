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
// Requires Version Preview URLs to be enabled on the worker (Cloudflare dash →
// the worker → Domains → Worker URL → Preview row). That toggle is SHARED and
// fragile: a `versions upload` does not carry the `preview_urls` config, and in
// practice the toggle can flip back off — which silently 404s every branch's
// preview stand. `wrangler` can't flip it back (only a full `wrangler deploy`
// applies the config, which we must NOT run from a feature branch), so this
// script can't self-heal it — instead it actively checks and shouts, turning
// that silent mine into a loud, actionable failure.
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

const TOGGLE_HINT =
  "Enable it: Cloudflare dash → stigla-backend-staging → Domains → Worker URL →\n" +
  "the Preview row (leave the Production row off), then re-run. See docs/staging.md.";

// wrangler prints e.g. "Version Preview URL: https://<prefix>-<worker>.<sub>.workers.dev"
const match = stdout.match(/Version Preview URL:\s*(https:\/\/\S+)/i);
if (!match) {
  console.error(
    "\n✗ staging:version — no preview URL in wrangler output.\n" +
      "The Version Preview URLs toggle is OFF on stigla-backend-staging, so this\n" +
      "upload has no reachable stand — AND every other branch's preview stand is\n" +
      "down too (they share this one toggle).\n" +
      TOGGLE_HINT,
  );
  process.exit(1);
}

const url = match[1];

// The toggle can be on at upload time yet flip off moments later, silently
// 404ing the URL we just printed. Verify it actually serves before handing it
// downstream. Best-effort: a network hiccup shouldn't fail the whole run.
const live = await isLive(`${url}/api/v1/config`);
if (live === false) {
  console.error(
    `\n✗ staging:version — preview URL was printed but ${url} does not respond\n` +
      "(HTTP error / no route). The Version Preview URLs toggle has been reset, so\n" +
      "this stand — and every other branch's preview stand — is down.\n" +
      TOGGLE_HINT,
  );
  process.exit(1);
}

// Reachable (or the check was inconclusive) — hand it off, but flag the shared,
// fragile nature so a later 404 isn't a mystery.
console.warn(
  "\n⚠ Heads-up: Version Preview URLs is a SHARED toggle. A `versions upload`\n" +
    "from any branch can flip it off and 404 every branch's preview stand (this\n" +
    "run may likewise have affected others). If a stand goes blank, re-enable it.\n" +
    TOGGLE_HINT,
);

// Machine-graspable final line for the next step to pick up.
console.log(`\nPREVIEW_URL=${url}`);

/**
 * @returns {Promise<boolean|null>} true = serving, false = definitely down
 *   (no route → toggle off), null = couldn't tell (don't block on it).
 */
async function isLive(target) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const r = await fetch(target, { signal: controller.signal });
    if (r.ok) return true; // 2xx — the version is serving
    if (r.status === 404) return false; // no route — the toggle is off
    return null; // 401/403/5xx/cold start — inconclusive, don't hard-fail
  } catch {
    return null; // network error / abort — inconclusive
  } finally {
    clearTimeout(timer);
  }
}
