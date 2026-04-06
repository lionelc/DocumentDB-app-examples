#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 9 "Custom Image Tag"

ensure_main_container || { echo "SKIP: container unavailable"; exit 1; }
echo "--- Running inspector with explicit :latest tag (as 'custom' tag) ---"
"$INSPECTOR" --password "$PASSWORD" --port "$MAIN_PORT" \
    --container "$MAIN_CONTAINER" --tls required \
    --image "$IMAGE"
rc=$?
echo ""
echo "Image used: $IMAGE"
exit $rc
