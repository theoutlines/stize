#!/usr/bin/env bash
# Copy the pinned MapLibre GL JS build (package.json here) into app/web/vendor/maplibre-gl,
# which index.html loads from our own domain instead of a CDN. Run after Dependabot bumps
# the version; CI (check.sh) fails until the copy matches the pin.
set -euo pipefail
cd "$(dirname "$0")"
npm ci --ignore-scripts --silent
OUT=../../web/vendor/maplibre-gl
mkdir -p "$OUT"
cp node_modules/maplibre-gl/dist/maplibre-gl.js node_modules/maplibre-gl/dist/maplibre-gl.css node_modules/maplibre-gl/LICENSE.txt "$OUT/"
echo "maplibre-gl $(node -p 'require("./package.json").dependencies["maplibre-gl"]') copied to app/web/vendor/maplibre-gl"
