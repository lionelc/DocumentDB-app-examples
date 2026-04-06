#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 6 "Authentication Failure"

ensure_main_container || { echo "SKIP: container unavailable"; exit 1; }
echo "--- Running inspector with WRONG password against running container ---"
"$INSPECTOR" --password "WRONG_PASSWORD_XYZ" --port "$MAIN_PORT" \
    --container "$MAIN_CONTAINER" --tls required
rc=$?
echo "Expected: AUTH_FAILED  |  Inspector exit code: $rc"
