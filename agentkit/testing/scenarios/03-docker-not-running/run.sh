#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 3 "Docker Not Running (simulated)"

echo "--- Simulating unreachable Docker daemon via DOCKER_HOST ---"
DOCKER_HOST="unix:///tmp/nonexistent_docker_$$.sock" \
    "$INSPECTOR" --password "$PASSWORD" --port 10299
rc=$?
echo "Expected: DOCKER_NOT_FOUND  |  Inspector exit code: $rc"
