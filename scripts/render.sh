#!/usr/bin/env bash
# render.sh — host-side launcher for the swgraph renderer.
# Mounts examples/ as /input and out/ as /output, then runs the in-container
# render-batch.sh via podman.
#
# Usage:
#   ./scripts/render.sh                    # uses ./examples and ./out
#   ./scripts/render.sh path/to/inputs out # custom dirs

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${1:-$REPO/examples}"
OUTPUT="${2:-$REPO/out}"
IMAGE="${IMAGE:-swgraph:latest}"
ENGINE="${ENGINE:-podman}"

[ -d "$INPUT" ] || { echo "input dir not found: $INPUT" >&2; exit 1; }
mkdir -p "$OUTPUT"

# Mount the in-container script from the repo so we can iterate without
# rebuilding the image.
SCRIPT_HOST="$REPO/scripts/render-batch.sh"
SCRIPT_CTR="/opt/swgraph/scripts/render-batch.sh"

echo "== swgraph render =="
echo "  input  : $INPUT"
echo "  output : $OUTPUT"
echo "  image  : $IMAGE"
echo

"$ENGINE" run --rm \
    -v "$INPUT:/input:ro,z" \
    -v "$OUTPUT:/output:z" \
    -v "$SCRIPT_HOST:$SCRIPT_CTR:ro,z" \
    --entrypoint /bin/bash \
    "$IMAGE" \
    "$SCRIPT_CTR"

echo
echo "Open the gallery: file://$OUTPUT/index.html"
echo "Or serve it     : ./scripts/serve.sh"
