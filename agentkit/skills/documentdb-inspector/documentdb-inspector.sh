#!/usr/bin/env bash
set -uo pipefail

########################################################################
# documentdb-inspector.sh  —  DocumentDB Local Instance Inspector
#
# Runs health checks against a DocumentDB local Docker container:
#   1. Docker daemon availability
#   2. Image availability (pull if needed)
#   3. Container startup / verification
#   4. Port reachability
#   5. TLS handshake
#   6. CRUD smoke test
#
# Modes:
#   Default:        Pull image → start container → run all checks
#   --container N:  Use existing container N (skip pull/create)
#   --check-only:   Skip Docker/image/container; only port/TLS/CRUD
########################################################################

readonly SCRIPT_VERSION="1.0.0"

# ── Defaults ──────────────────────────────────────────────────────────
IMAGE="ghcr.io/documentdb/documentdb/documentdb-local:latest"
HOST_PORT=10260
DB_USER="docdbadmin"
DB_PASSWORD=""
TLS_MODE="off"
TIMEOUT=120
KEEP=false
CONTAINER_NAME=""
CHECK_ONLY=false
JSON_ONLY=false
REPORT_FILE=""

# ── State ─────────────────────────────────────────────────────────────
CREATED_CONTAINER=""
OVERALL_STATUS="PASS"
R_NAMES=()
R_STATUS=()
R_DURATION=()
R_ERRCODE=()
R_ERROR=()

# ── Helpers ───────────────────────────────────────────────────────────
log() { echo "[inspector] $*" >&2; }

record() {
    local name="$1" status="$2" dur="${3:-0}" ecode="${4:-}" emsg="${5:-}"
    R_NAMES+=("$name")
    R_STATUS+=("$status")
    R_DURATION+=("$dur")
    R_ERRCODE+=("$ecode")
    R_ERROR+=("$emsg")
    if [[ "$status" == "FAIL" ]]; then OVERALL_STATUS="FAIL"; fi
    return 0
}

ms_since() {
    local now; now=$(date +%s%N)
    echo $(( (now - $1) / 1000000 ))
}

conn_uri() {
    local u="${1:-$DB_USER}" p="${2:-$DB_PASSWORD}"
    if [[ "$TLS_MODE" == "off" ]]; then
        echo "mongodb://${u}:${p}@localhost:${HOST_PORT}/?directConnection=true"
    else
        echo "mongodb://${u}:${p}@localhost:${HOST_PORT}/?tls=true&tlsAllowInvalidCertificates=true&directConnection=true"
    fi
}

# ── Argument parsing ──────────────────────────────────────────────────
usage() {
    cat <<'EOF'
documentdb-inspector.sh — DocumentDB Local Instance Inspector

Usage: documentdb-inspector.sh --password <pass> [OPTIONS]

Options:
  --image IMAGE        Docker image (default: ghcr.io/.../documentdb-local:latest)
  --port PORT          Host port (default: 10260)
  --user USER          Username (default: docdbadmin)
  --password PASS      Password (required)
  --tls MODE           required | prefer | off (default: off)
  --timeout SECS       Startup timeout (default: 120)
  --keep               Leave container running after checks
  --container NAME     Use existing container (skip pull/create)
  --check-only         Skip Docker/image/container; only check port/TLS/CRUD
  --json               Output JSON only (table suppressed)
  --report FILE        Save JSON report to file
  -h, --help           Show this help

Error Codes:
  DOCKER_NOT_FOUND      Docker daemon not reachable
  IMAGE_PULL_FAILED     Could not pull the image
  PORT_IN_USE           Host port already bound
  CONTAINER_FAILED      Container did not start or crashed
  PORT_UNREACHABLE      TCP connection to port failed
  TLS_HANDSHAKE_FAILED  TLS negotiation failed
  AUTH_FAILED           Authentication rejected
  CRUD_FAILED           CRUD smoke test failed
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image)       IMAGE="$2";           shift 2 ;;
            --port)        HOST_PORT="$2";        shift 2 ;;
            --user)        DB_USER="$2";          shift 2 ;;
            --password)    DB_PASSWORD="$2";      shift 2 ;;
            --tls)         TLS_MODE="$2";         shift 2 ;;
            --timeout)     TIMEOUT="${2%s}";       shift 2 ;;
            --keep)        KEEP=true;             shift ;;
            --container)   CONTAINER_NAME="$2";   shift 2 ;;
            --check-only)  CHECK_ONLY=true;       shift ;;
            --json)        JSON_ONLY=true;        shift ;;
            --report)      REPORT_FILE="$2";      shift 2 ;;
            -h|--help)     usage; exit 0 ;;
            *)             log "Unknown option: $1"; exit 1 ;;
        esac
    done
    [[ -z "$DB_PASSWORD" ]] && { log "--password is required"; exit 1; }
}

# ── Checks ────────────────────────────────────────────────────────────

check_docker() {
    local t; t=$(date +%s%N)
    log "Checking Docker daemon..."
    if ! command -v docker &>/dev/null; then
        record "Docker available" FAIL "$(ms_since "$t")" DOCKER_NOT_FOUND \
            "docker CLI not found in PATH"
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        record "Docker available" FAIL "$(ms_since "$t")" DOCKER_NOT_FOUND \
            "Docker daemon is not running or not accessible"
        return 1
    fi
    record "Docker available" PASS "$(ms_since "$t")"
}

check_image() {
    local t; t=$(date +%s%N)
    log "Checking image $IMAGE ..."
    if docker image inspect "$IMAGE" &>/dev/null; then
        record "Image pulled" PASS "$(ms_since "$t")" "" "cached"
        return 0
    fi
    log "Image not cached — pulling..."
    local out
    if out=$(docker pull "$IMAGE" 2>&1); then
        record "Image pulled" PASS "$(ms_since "$t")"
    else
        record "Image pulled" FAIL "$(ms_since "$t")" IMAGE_PULL_FAILED "$out"
        return 1
    fi
}

check_container() {
    local t; t=$(date +%s%N)

    # ── existing-container mode ──
    if [[ -n "$CONTAINER_NAME" ]]; then
        log "Verifying container $CONTAINER_NAME is running..."
        if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
            record "Container started" PASS "$(ms_since "$t")" "" "existing"
            return 0
        fi
        record "Container started" FAIL "$(ms_since "$t")" CONTAINER_FAILED \
            "Container '$CONTAINER_NAME' is not running"
        return 1
    fi

    # ── new-container mode ──
    log "Checking whether port $HOST_PORT is free..."
    if ss -tlnp 2>/dev/null | grep -q ":${HOST_PORT} "; then
        record "Container started" FAIL "$(ms_since "$t")" PORT_IN_USE \
            "Port $HOST_PORT is already in use on the host"
        return 1
    fi

    local cname="documentdb-inspector-$$"
    log "Starting container $cname  (port $HOST_PORT → 10260)..."
    local out
    out=$(docker run -dt \
        -p "${HOST_PORT}:10260" \
        --name "$cname" \
        "$IMAGE" \
        --username "$DB_USER" \
        --password "$DB_PASSWORD" 2>&1)
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        if echo "$out" | grep -qi "port.*already\|already allocated\|address already in use\|Bind"; then
            record "Container started" FAIL "$(ms_since "$t")" PORT_IN_USE "$out"
        else
            record "Container started" FAIL "$(ms_since "$t")" CONTAINER_FAILED "$out"
        fi
        return 1
    fi
    CREATED_CONTAINER="$cname"
    CONTAINER_NAME="$cname"

    # wait for readiness
    log "Waiting for container to accept connections (timeout ${TIMEOUT}s)..."
    local waited=0
    while (( waited < TIMEOUT )); do
        if ! docker ps --format '{{.Names}}' | grep -qx "$cname"; then
            local logs; logs=$(docker logs "$cname" 2>&1 | tail -30)
            record "Container started" FAIL "$(ms_since "$t")" CONTAINER_FAILED \
                "Container exited unexpectedly. Logs: $logs"
            return 1
        fi
        if mongosh "mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${HOST_PORT}/?tls=true&tlsAllowInvalidCertificates=true&directConnection=true" \
            --quiet --eval "db.runCommand({ping:1})" &>/dev/null 2>&1; then
            break
        fi
        sleep 3
        waited=$((waited + 3))
    done
    if (( waited >= TIMEOUT )); then
        local logs; logs=$(docker logs "$cname" 2>&1 | tail -30)
        record "Container started" FAIL "$(ms_since "$t")" CONTAINER_FAILED \
            "Container not ready after ${TIMEOUT}s. Logs: $logs"
        return 1
    fi
    record "Container started" PASS "$(ms_since "$t")"
}

check_port() {
    local t; t=$(date +%s%N)
    log "Checking port $HOST_PORT reachability..."
    if timeout 10 bash -c "echo >/dev/tcp/localhost/${HOST_PORT}" 2>/dev/null; then
        record "Port reachable" PASS "$(ms_since "$t")"
    else
        record "Port reachable" FAIL "$(ms_since "$t")" PORT_UNREACHABLE \
            "Cannot reach localhost:$HOST_PORT"
        return 1
    fi
}

check_tls() {
    local t; t=$(date +%s%N)
    if [[ "$TLS_MODE" == "off" ]]; then
        record "TLS handshake" SKIP 0 "" "TLS mode is off"
        return 0
    fi
    log "Checking TLS handshake on port $HOST_PORT ..."
    local out
    out=$(echo | timeout 10 openssl s_client -connect "localhost:${HOST_PORT}" 2>&1)

    if echo "$out" | grep -q "BEGIN CERTIFICATE"; then
        record "TLS handshake" PASS "$(ms_since "$t")"
        return 0
    fi

    local detail
    detail=$(echo "$out" | grep -iE "error|wrong version|routines|errno" | head -3)

    if [[ "$TLS_MODE" == "prefer" ]]; then
        TLS_MODE="off"
        record "TLS handshake" WARN "$(ms_since "$t")" "" \
            "TLS unavailable — falling back to plain text. $detail"
        return 0
    fi

    record "TLS handshake" FAIL "$(ms_since "$t")" TLS_HANDSHAKE_FAILED \
        "TLS handshake failed. $detail"
    return 1
}

check_crud() {
    local t; t=$(date +%s%N)
    log "Running CRUD smoke test..."
    local uri; uri=$(conn_uri)

    local js
    read -r -d '' js <<'JSEOF' || true
var tdb = db.getSiblingDB("__inspector_test");
tdb.dropDatabase();
tdb = db.getSiblingDB("__inspector_test");
var ir = tdb.smoke_test.insertOne({k:"inspector",v:42,ts:new Date()});
if (!ir.insertedId) throw new Error("INSERT failed");
var d = tdb.smoke_test.findOne({k:"inspector"});
if (!d || d.v !== 42) throw new Error("READ failed");
var ur = tdb.smoke_test.updateOne({k:"inspector"},{$set:{v:99}});
if (ur.modifiedCount !== 1) throw new Error("UPDATE failed");
d = tdb.smoke_test.findOne({k:"inspector"});
if (d.v !== 99) throw new Error("READ-after-UPDATE failed");
var dr = tdb.smoke_test.deleteOne({k:"inspector"});
if (dr.deletedCount !== 1) throw new Error("DELETE failed");
tdb.dropDatabase();
print("CRUD_OK");
JSEOF

    local out
    out=$(mongosh "$uri" --quiet --eval "$js" 2>&1)

    if echo "$out" | grep -q "CRUD_OK"; then
        record "Smoke test (CRUD)" PASS "$(ms_since "$t")"
        return 0
    fi

    if echo "$out" | grep -qi "authentication failed\|auth.*fail\|AuthenticationFailed\|Invalid key\|SCRAM"; then
        record "Smoke test (CRUD)" FAIL "$(ms_since "$t")" AUTH_FAILED "$out"
    else
        record "Smoke test (CRUD)" FAIL "$(ms_since "$t")" CRUD_FAILED "$out"
    fi
    return 1
}

# ── Output: human-readable table ──────────────────────────────────────

print_table() {
    echo ""
    echo "================================================================"
    echo " DocumentDB Inspector Report   v$SCRIPT_VERSION"
    echo "================================================================"
    printf "  %-25s %-12s %8s  %s\n" "Check" "Status" "Duration" "Code"
    echo "----------------------------------------------------------------"
    for i in "${!R_NAMES[@]}"; do
        local icon
        case "${R_STATUS[$i]}" in
            PASS) icon="PASS" ;;
            FAIL) icon="FAIL" ;;
            WARN) icon="WARN" ;;
            SKIP) icon="SKIP" ;;
        esac
        printf "  %-25s %-12s %5s ms  %s\n" \
            "${R_NAMES[$i]}" "$icon" "${R_DURATION[$i]}" "${R_ERRCODE[$i]}"
    done
    echo "----------------------------------------------------------------"
    if [[ "$OVERALL_STATUS" == "PASS" ]]; then
        echo "  Overall: ALL CHECKS PASSED — system is healthy"
    else
        echo "  Overall: ISSUES DETECTED — see findings below"
    fi
    echo "================================================================"
    echo ""

    # Findings details + fix suggestions
    for i in "${!R_NAMES[@]}"; do
        [[ "${R_STATUS[$i]}" != "FAIL" ]] && continue
        echo "FINDING: ${R_NAMES[$i]}  (${R_ERRCODE[$i]})"
        echo "  ${R_ERROR[$i]}"
        echo ""
        echo "  Suggested resolution:"
        case "${R_ERRCODE[$i]}" in
            DOCKER_NOT_FOUND)
                echo "    1. Start Docker daemon:  sudo systemctl start docker"
                echo "    2. Install Docker:       https://docs.docker.com/get-docker/" ;;
            IMAGE_PULL_FAILED)
                echo "    1. Check network / proxy settings"
                echo "    2. Pull manually:  docker pull $IMAGE"
                echo "    3. Air-gapped env: docker save / docker load" ;;
            PORT_IN_USE)
                echo "    1. Find occupant:  ss -tlnp | grep $HOST_PORT"
                echo "    2. Free the port or re-run with --port <other>" ;;
            TLS_HANDSHAKE_FAILED)
                echo "    1. Re-run with --tls off or --tls prefer"
                echo "    2. Ensure the container was started with TLS support"
                echo "    3. For dev use, --tls off is acceptable" ;;
            AUTH_FAILED)
                echo "    1. Verify --user / --password match container credentials"
                echo "    2. Remove container & volume, then recreate if credentials changed" ;;
            CRUD_FAILED)
                echo "    1. docker logs ${CONTAINER_NAME:-<container>}"
                echo "    2. Verify instance finished initialising"
                echo "    3. Try connecting manually with mongosh" ;;
        esac
        echo ""
    done

    if [[ -n "$CREATED_CONTAINER" && "$KEEP" == true ]]; then
        echo "Container '$CREATED_CONTAINER' left running (--keep)."
        echo "  Connect:  mongosh \"$(conn_uri "$DB_USER" '****')\""
        echo "  Cleanup:  docker rm -f $CREATED_CONTAINER"
        echo ""
    fi
}

# ── Output: JSON ──────────────────────────────────────────────────────

emit_json() {
    [[ -z "$REPORT_FILE" && "$JSON_ONLY" != true ]] && return

    local tmpdir; tmpdir=$(mktemp -d)

    echo "$OVERALL_STATUS"   > "$tmpdir/overall"
    echo "$IMAGE"            > "$tmpdir/image"
    echo "$HOST_PORT"        > "$tmpdir/port"
    echo "$TLS_MODE"         > "$tmpdir/tls"
    echo "$CONTAINER_NAME"   > "$tmpdir/container"
    echo "${#R_NAMES[@]}"    > "$tmpdir/count"

    for i in "${!R_NAMES[@]}"; do
        echo "${R_NAMES[$i]}"    > "$tmpdir/name_$i"
        echo "${R_STATUS[$i]}"   > "$tmpdir/status_$i"
        echo "${R_DURATION[$i]}" > "$tmpdir/dur_$i"
        echo "${R_ERRCODE[$i]}"  > "$tmpdir/ecode_$i"
        printf '%s' "${R_ERROR[$i]}" > "$tmpdir/err_$i"
    done

    local json
    json=$(TMPDIR_PATH="$tmpdir" python3 -c '
import json, os
d = os.environ["TMPDIR_PATH"]
def rd(f):
    with open(os.path.join(d, f)) as fh:
        return fh.read().strip()
data = {
    "overallStatus": rd("overall"),
    "image":         rd("image"),
    "port":          int(rd("port")),
    "tlsMode":       rd("tls"),
    "container":     rd("container"),
    "checks":        []
}
n = int(rd("count"))
for i in range(n):
    dur = rd(f"dur_{i}")
    data["checks"].append({
        "name":       rd(f"name_{i}"),
        "status":     rd(f"status_{i}"),
        "durationMs": int(dur) if dur.lstrip("-").isdigit() else 0,
        "errorCode":  rd(f"ecode_{i}"),
        "error":      rd(f"err_{i}")
    })
print(json.dumps(data, indent=2))
')

    rm -rf "$tmpdir"

    if [[ -n "$REPORT_FILE" ]]; then
        echo "$json" > "$REPORT_FILE"
        log "Report saved to $REPORT_FILE"
    fi
    [[ "$JSON_ONLY" == true ]] && echo "$json"
}

# ── Cleanup ───────────────────────────────────────────────────────────

cleanup() {
    if [[ -n "$CREATED_CONTAINER" && "$KEEP" != true ]]; then
        log "Cleaning up container $CREATED_CONTAINER ..."
        docker rm -f "$CREATED_CONTAINER" &>/dev/null || true
    fi
}

# ── Main ──────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    trap cleanup EXIT

    log "DocumentDB Inspector v$SCRIPT_VERSION"
    log "Image: $IMAGE | Port: $HOST_PORT | TLS: $TLS_MODE | Timeout: ${TIMEOUT}s"

    if [[ "$CHECK_ONLY" == true ]]; then
        check_port   || true
        check_tls    || true
        # only try CRUD if port was reachable
        local last=${R_STATUS[${#R_STATUS[@]}-1]:-FAIL}
        if [[ "$last" == "PASS" || "$last" == "WARN" || "$last" == "SKIP" ]]; then
            check_crud || true
        fi
    else
        check_docker || { print_table; emit_json; return 1; }
        if [[ -z "$CONTAINER_NAME" ]]; then
            check_image || { print_table; emit_json; return 1; }
        fi
        check_container || { print_table; emit_json; return 1; }
        check_port      || { print_table; emit_json; return 1; }
        check_tls       || { print_table; emit_json; return 1; }
        check_crud      || true
    fi

    [[ "$JSON_ONLY" != true ]] && print_table
    emit_json

    [[ "$OVERALL_STATUS" == "PASS" ]]
}

main "$@"
