#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 7 "Image Pull Failure"

echo "--- Running inspector with non-existent image tag ---"
"$INSPECTOR" --password "$PASSWORD" \
    --image "ghcr.io/documentdb/documentdb/documentdb-local:nonexistent-99.99.99" \
    --port 10272
rc=$?
echo "Expected: IMAGE_PULL_FAILED  |  Inspector exit code: $rc"
