#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 2 "Happy Path — Is my local DocumentDB working?"
ensure_main_container || { echo "SKIP: container unavailable"; exit 1; }
"$INSPECTOR" --password "$PASSWORD" --port "$MAIN_PORT" \
    --container "$MAIN_CONTAINER" --tls required
