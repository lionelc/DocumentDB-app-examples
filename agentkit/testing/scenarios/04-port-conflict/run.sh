#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 4 "Port Conflict"

CONFLICT_PORT=10270

echo "--- Starting a TCP listener on port $CONFLICT_PORT ---"
python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', $CONFLICT_PORT))
s.listen(5)
time.sleep(600)
" &
LISTENER_PID=$!
sleep 1

cleanup_listener() { kill "$LISTENER_PID" 2>/dev/null; wait "$LISTENER_PID" 2>/dev/null || true; }
trap cleanup_listener EXIT

echo "--- Running inspector against occupied port $CONFLICT_PORT ---"
"$INSPECTOR" --password "$PASSWORD" --port "$CONFLICT_PORT"
rc=$?

echo "Expected: PORT_IN_USE  |  Inspector exit code: $rc"
