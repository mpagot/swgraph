#!/usr/bin/env bash
# serve.sh — host-side launcher to serve the rendered gallery.
# Runs python3 -m http.server inside the swgraph container, mounted on
# the local out/ directory. Default port 8080.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$REPO/out}"
PORT="${PORT:-8080}"
IMAGE="${IMAGE:-swgraph:latest}"
ENGINE="${ENGINE:-podman}"

[ -d "$OUTPUT" ] || { echo "no output dir at $OUTPUT — run render.sh first" >&2; exit 1; }

echo "Serving $OUTPUT at http://localhost:$PORT/"
echo "Ctrl-C to stop."

exec "$ENGINE" run --rm -it \
    -v "$OUTPUT:/output:ro,z" \
    -p "$PORT:8080" \
    --entrypoint python3 \
    "$IMAGE" \
    -m http.server 8080 --directory /output
