#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 11 "Compatibility Tests (documentdb/functional-tests)"

########################################################################
# This scenario clones the official DocumentDB functional-tests repo
# on demand and runs the pytest suite against a live DocumentDB container.
########################################################################

FUNC_TESTS_REPO="https://github.com/documentdb/functional-tests.git"
FUNC_TESTS_DIR=""

cleanup_func_tests() {
    if [[ -n "$FUNC_TESTS_DIR" && -d "$FUNC_TESTS_DIR" ]]; then
        echo "[cleanup] Removing functional-tests clone: $FUNC_TESTS_DIR"
        rm -rf "$FUNC_TESTS_DIR"
    fi
}
trap cleanup_func_tests EXIT

# ── Step 1: Ensure DocumentDB container ──────────────────────────────
echo "--- Step 1: Ensure DocumentDB container is running ---"
ensure_main_container || { echo "FAIL: Could not start DocumentDB container"; exit 1; }
echo ""

# ── Step 2: Download functional tests ────────────────────────────────
FUNC_TESTS_DIR=$(mktemp -d)
echo "--- Step 2: Downloading functional-tests from GitHub ---"
echo "  Repo:   $FUNC_TESTS_REPO"
echo "  Target: $FUNC_TESTS_DIR"
echo ""

git clone --depth 1 "$FUNC_TESTS_REPO" "$FUNC_TESTS_DIR" 2>&1
echo ""

# ── Step 3: Install Python dependencies ──────────────────────────────
echo "--- Step 3: Setting up Python virtual environment and dependencies ---"
VENV_DIR="$FUNC_TESTS_DIR/.venv"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install -q -r "$FUNC_TESTS_DIR/requirements.txt" 2>&1
echo ""

# ── Step 4: Run the test suite ───────────────────────────────────────
CONN_STR="mongodb://${USER}:${PASSWORD}@localhost:${MAIN_PORT}/?tls=true&tlsAllowInvalidCertificates=true&directConnection=true"
RESULTS_DIR="$FUNC_TESTS_DIR/.test-results"
mkdir -p "$RESULTS_DIR"

echo "--- Step 4: Running compatibility tests ---"
echo "  Connection: mongodb://${USER}:****@localhost:${MAIN_PORT}/..."
echo "  Engine:     documentdb"
echo ""

pytest "$FUNC_TESTS_DIR/documentdb_tests/" \
    --connection-string "$CONN_STR" \
    --engine-name documentdb \
    -v \
    --tb=short \
    --no-header \
    --json-report --json-report-file="$RESULTS_DIR/report.json" \
    2>&1
TEST_EXIT=$?

echo ""

# ── Step 5: Report results ───────────────────────────────────────────
echo "--- Step 5: Test results summary ---"
if [[ -f "$RESULTS_DIR/report.json" ]]; then
    python3 -c "
import json, sys
with open('$RESULTS_DIR/report.json') as f:
    data = json.load(f)

summary = data.get('summary', {})
total    = summary.get('total', 0)
passed   = summary.get('passed', 0)
failed   = summary.get('failed', 0)
errors   = summary.get('error', 0)
skipped  = summary.get('skipped', 0)
xfailed  = summary.get('xfailed', 0)
duration = data.get('duration', 0)

print(f'  Total:    {total}')
print(f'  Passed:   {passed}')
print(f'  Failed:   {failed}')
print(f'  Errors:   {errors}')
print(f'  Skipped:  {skipped}')
print(f'  XFailed:  {xfailed}')
print(f'  Duration: {duration:.1f}s')
print()

if failed > 0 or errors > 0:
    print('  Failed/errored tests:')
    for t in data.get('tests', []):
        if t.get('outcome') in ('failed', 'error'):
            name = t.get('nodeid', 'unknown')
            msg  = ''
            call = t.get('call', {})
            if call:
                crash = call.get('crash', {})
                msg = crash.get('message', '')[:120]
            print(f'    FAIL  {name}')
            if msg:
                print(f'          {msg}')
"
else
    echo "  (no JSON report generated)"
fi

echo ""
if [[ $TEST_EXIT -eq 0 ]]; then
    echo "  Result: ALL TESTS PASSED"
else
    echo "  Result: SOME TESTS DID NOT PASS (exit code $TEST_EXIT)"
    echo "  Note:   Failures may indicate DocumentDB compatibility gaps —"
    echo "          this is expected inspector behaviour (exposing issues)."
fi

exit $TEST_EXIT
