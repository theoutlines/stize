#!/usr/bin/env bash
# Cloudflare Pages build for the Flutter web app (Git integration).
#
# Pages runs this from the repo root on every push:
#   build command:     bash app/tool/cf_pages_build.sh
#   output directory:  app/build/web
#
# - `main` is production: same bundle as the old manual release
#   (default API https://api.stize.app, no ENVIRONMENT define).
# - Every other branch is a preview pointed at the staging API, with the
#   STAGING badge on, so in-development flags (ON on staging) are exercised.
# - The MapTiler client key comes from the Pages project variable MAPTILER_KEY
#   (never from the repo); dart_defines.json is written only for the build and
#   removed afterwards.
# - app/web/_worker.js (preview password gate + www redirect) is copied into the
#   output by `flutter build web`, so Pages keeps running it as before.
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
if [ "${BRANCH}" != "main" ]; then
  EXTRA_DEFINES+=(
    "--dart-define=API_BASE_URL=https://api-staging.stize.app"
    "--dart-define=ENVIRONMENT=staging"
  )
fi
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
  grep -q "api-staging.stize.app" build/web/main.dart.js
fi
echo "OK: build/web ready"
