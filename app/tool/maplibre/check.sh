#!/usr/bin/env bash
# CI: the vendored MapLibre file must be the version pinned in package.json.
set -euo pipefail
cd "$(dirname "$0")"
want="$(node -p 'require("./package.json").dependencies["maplibre-gl"]')"
have="$(head -c 400 ../../web/vendor/maplibre-gl/maplibre-gl.js | grep -oE 'blob/v[0-9.]+' | cut -c7-)"
[ "$want" = "$have" ] || { echo "app/web/vendor/maplibre-gl is v$have, package.json pins v$want: run app/tool/maplibre/sync.sh"; exit 1; }
echo "maplibre-gl vendored v$have matches the pin"
