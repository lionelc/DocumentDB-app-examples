#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 0 "Starting a DocumentDB Local Container from Scratch"

cleanup_main_container

echo "--- Step 1: Pull the official image ---"
docker pull "$IMAGE"
echo ""

echo "--- Step 2: Start the container (with --skip-init-data for clean testing) ---"
docker run -dt -p "${MAIN_PORT}:10260" --name "$MAIN_CONTAINER" \
    "$IMAGE" --username "$USER" --password "$PASSWORD" --skip-init-data
echo ""

echo "--- Step 3: Wait for readiness ---"
wait_for_main_container || exit 1
echo ""

echo "--- Step 4: Verify with inspector ---"
"$INSPECTOR" --password "$PASSWORD" --port "$MAIN_PORT" \
    --container "$MAIN_CONTAINER" --tls required
rc=$?

separator
echo "Connection string:"
echo "  mongosh \"mongodb://${USER}:${PASSWORD}@localhost:${MAIN_PORT}/?tls=true&tlsAllowInvalidCertificates=true\""
exit $rc
