#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

# Usage:
#   run.sh              — default: simulate TLS failure (plain TCP server)
#   run.sh --happy      — TLS happy path against real DocumentDB container

MODE="failure"
[[ "${1:-}" == "--happy" ]] && MODE="happy"

if [[ "$MODE" == "happy" ]]; then
    banner 5 "TLS Handshake — Happy Path (real DocumentDB with TLS)"

    ensure_main_container || { echo "SKIP: container unavailable"; exit 1; }

    echo "--- Running inspector with --tls required against DocumentDB container ---"
    "$INSPECTOR" --password "$PASSWORD" --port "$MAIN_PORT" \
        --container "$MAIN_CONTAINER" --tls required
    rc=$?
    echo "Expected: TLS handshake PASS  |  Inspector exit code: $rc"
else
    banner 5 "TLS Handshake Failure (simulated plain-text server)"

    TLS_PORT=10271

    echo "--- Starting plain-text TCP server on port $TLS_PORT (no TLS) ---"
    python3 -c "
import socket, threading, time
def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', $TLS_PORT))
    s.listen(5)
    while True:
        try:
            conn, _ = s.accept()
            conn.sendall(b'HELLO plain text\r\n')
            time.sleep(0.5)
            conn.close()
        except: break
t = threading.Thread(target=serve, daemon=True)
t.start()
time.sleep(600)
" &
    SERVER_PID=$!
    sleep 1

    cleanup_server() { kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null || true; }
    trap cleanup_server EXIT

    echo "--- Running inspector with --tls required --check-only ---"
    "$INSPECTOR" --password "$PASSWORD" --port "$TLS_PORT" --tls required --check-only
    rc=$?

    echo "Expected: TLS_HANDSHAKE_FAILED  |  Inspector exit code: $rc"
fi
