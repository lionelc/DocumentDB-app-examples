#!/usr/bin/env bash
# helpers.sh — Common functions for the DocumentDB Inspector test harness

IMAGE="ghcr.io/documentdb/documentdb/documentdb-local:latest"
PASSWORD="Test1234"
USER="docdbadmin"
MAIN_PORT=10260
MAIN_CONTAINER="documentdb-test-main"
HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HELPERS_DIR/../.." && pwd)"
INSPECTOR="${REPO_ROOT}/skills/documentdb-inspector/documentdb-inspector.sh"
CONN_URI="mongodb://${USER}:${PASSWORD}@localhost:${MAIN_PORT}/?tls=true&tlsAllowInvalidCertificates=true&directConnection=true"

banner() {
    local num="$1" title="$2"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  SCENARIO $num: $title"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

separator() { echo "────────────────────────────────────────────────────"; }

cleanup_inspector_containers() {
    local names
    names=$(docker ps -aq --filter "name=documentdb-inspector" 2>/dev/null)
    if [[ -n "$names" ]]; then
        echo "$names" | xargs docker rm -f 2>/dev/null || true
    fi
}

cleanup_main_container() {
    docker rm -f "$MAIN_CONTAINER" 2>/dev/null || true
}

wait_for_main_container() {
    echo "[setup] Waiting for $MAIN_CONTAINER to be ready (up to 120 s)..."
    local waited=0
    while (( waited < 120 )); do
        if mongosh "$CONN_URI" --quiet --eval "db.runCommand({ping:1})" &>/dev/null 2>&1; then
            echo "[setup] Container ready after ${waited}s"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    echo "[setup] TIMEOUT: container not ready after 120s"
    docker logs "$MAIN_CONTAINER" 2>&1 | tail -30
    return 1
}

ensure_main_container() {
    if docker ps --format '{{.Names}}' | grep -qx "$MAIN_CONTAINER" 2>/dev/null; then
        if mongosh "$CONN_URI" --quiet --eval "db.runCommand({ping:1})" &>/dev/null 2>&1; then
            return 0
        fi
    fi
    echo "[setup] Main container not running or unhealthy — restarting..."
    docker rm -f "$MAIN_CONTAINER" 2>/dev/null || true
    docker run -dt -p "${MAIN_PORT}:10260" --name "$MAIN_CONTAINER" \
        "$IMAGE" --username "$USER" --password "$PASSWORD" --skip-init-data
    wait_for_main_container
}
