#!/usr/bin/env bash
# Cloudflare Pages build for the Flutter web app (Git integration).
#
# Pages runs this from the repo root on every push:
#   build command:     bash app/tool/cf_pages_build.sh
#   output directory:  app/build/web
#
# - `main` is production: same bundle as the old manual release
#   (default API https://api.stize.app, no ENVIRONMENT define).
# - Every other branch is a staging preview (STAGING badge, in-development flags
#   ON). It talks to *its own* backend version: Workers Builds uploads each
#   branch push of stigla-backend-staging as a version with a branch preview
#   alias, https://<branch-slug>-stigla-backend-staging.theoutlines.workers.dev,
#   so web + API of one branch form an isolated pair (the internal environments notes). If that
#   alias doesn't answer in time, the build falls back to the shared staging API
#   https://api-staging.stize.app and says so in the log.
# - The MapTiler client key comes from the Pages project variable MAPTILER_KEY
#   (never from the repo); dart_defines.json is written only for the build and
#   removed afterwards.
# - No Pages worker: previews are gated by Cloudflare Access (Pages > Settings >
#   Preview access) and www.stize.app -> stize.app is a zone Redirect Rule, so
#   static requests never run a worker. Headers come from app/web/_headers.
set -euo pipefail

# Keep in sync with app/.metadata (revision f94f4fc76b4d = tag 3.44.5).
FLUTTER_VERSION="3.44.5"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DIR="${HOME}/flutter-${FLUTTER_VERSION}"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version

: "${MAPTILER_KEY:?MAPTILER_KEY is not set in the Pages project variables}"

BRANCH="${CF_PAGES_BRANCH:-}"
EXTRA_DEFINES=()
API_URL="https://api.stize.app"
if [ "${BRANCH}" != "main" ]; then
  # Same slug rule as the worker preview alias: lowercase, non-alnum -> '-'.
  SLUG="$(printf '%s' "${BRANCH}" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  ALIAS_URL="https://${SLUG}-stigla-backend-staging.theoutlines.workers.dev"
  API_URL="https://api-staging.stize.app"
  # The backend build for this push usually finishes first; wait up to ~4 min.
  for _ in $(seq 1 24); do
    if curl -fsS --max-time 10 "${ALIAS_URL}/api/v1/config" 2>/dev/null \
        | grep -q '"staging"'; then
      API_URL="${ALIAS_URL}"
      break
    fi
    sleep 10
  done
  [ "${API_URL}" = "${ALIAS_URL}" ] \
    || echo "WARN: branch backend ${ALIAS_URL} not reachable; using shared staging API"
  EXTRA_DEFINES+=(
    "--dart-define=API_BASE_URL=${API_URL}"
    "--dart-define=ENVIRONMENT=staging"
  )
fi
echo "API for this build: ${API_URL}"
echo "Building branch '${BRANCH:-unknown}' ($([ "${BRANCH}" = "main" ] && echo production || echo staging preview))"

cd "${ROOT}/app"
printf '{"MAPTILER_KEY":"%s"}\n' "${MAPTILER_KEY}" > dart_defines.json
trap 'rm -f "${ROOT}/app/dart_defines.json"' EXIT

flutter pub get
flutter build web --release --dart-define-from-file=dart_defines.json "${EXTRA_DEFINES[@]}"

# Sanity check: the bundle must point at the API this branch expects.
if [ "${BRANCH}" = "main" ]; then
  grep -q "api.stize.app" build/web/main.dart.js
  ! grep -q "api-staging.stize.app" build/web/main.dart.js
else
  grep -qF "${API_URL#https://}" build/web/main.dart.js
fi
# Static, indexable stop and line pages + sitemap (the Flutter canvas is
# invisible to search engines). Plain HTML, no live requests.
node "${ROOT}/app/tool/gen_seo_pages.mjs" "${ROOT}/backend/public/gtfs" "${ROOT}/app/build/web"
test -f build/web/sitemap.xml

echo "OK: build/web ready"
