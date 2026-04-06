#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 8 "Keep Container for Debugging"

KEEP_PORT=10273

echo "--- Running inspector with --keep ---"
"$INSPECTOR" --password "$PASSWORD" --port "$KEEP_PORT" --keep --tls required
rc=$?
echo ""

echo "--- Checking that container is still running ---"
docker ps --filter "name=documentdb-inspector" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "--- Cleaning up kept container ---"
cleanup_inspector_containers
echo "Done."
exit $rc
