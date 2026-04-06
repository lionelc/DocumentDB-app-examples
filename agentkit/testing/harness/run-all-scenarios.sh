#!/usr/bin/env bash
set -uo pipefail

########################################################################
# run-all-scenarios.sh
#
# Exercises DocumentDB Inspector scenarios, captures output to a log.
#
# Usage:
#   bash run-all-scenarios.sh          # run all scenarios (0–10)
#   bash run-all-scenarios.sh 4        # run only scenario 4
#   bash run-all-scenarios.sh 3 4 5    # run scenarios 3, 4, and 5
########################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/../scenarios"

source "$SCRIPT_DIR/helpers.sh"

TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOGFILE="${REPO_ROOT}/agent-kit-inspector-scenarios-runlog-${TIMESTAMP}.log"

# Resolve which scenarios to run
SCENARIO_DIRS=()
if [[ $# -gt 0 ]]; then
    for num in "$@"; do
        padded=$(printf "%02d" "$num")
        match=$(ls -d "$SCENARIOS_DIR/${padded}-"* 2>/dev/null | head -1)
        if [[ -z "$match" ]]; then
            echo "ERROR: No scenario directory found for number $num" >&2; exit 1
        fi
        SCENARIO_DIRS+=("$match")
    done
else
    for d in "$SCENARIOS_DIR"/[0-9]*/; do
        [[ -f "$d/run.sh" ]] && SCENARIO_DIRS+=("$d")
    done
fi

SCENARIO_RESULTS=()

main() {
    echo "========================================================================"
    echo "  DocumentDB Inspector — Scenario Test Run"
    echo "  Date: $(date)"
    echo "  Scenarios: ${#SCENARIO_DIRS[@]}"
    echo "  Log:  $LOGFILE"
    echo "========================================================================"

    # Pre-flight cleanup
    cleanup_inspector_containers
    if [[ $# -eq 0 ]]; then
        cleanup_main_container
    fi

    for dir in "${SCENARIO_DIRS[@]}"; do
        local name; name=$(basename "$dir")
        local num; num=${name%%-*}
        bash "$dir/run.sh" 2>&1
        local rc=$?
        SCENARIO_RESULTS+=("Scenario $num  →  exit $rc  ($name)")
        separator
    done

    # Final cleanup
    echo ""
    echo "[cleanup] Final cleanup..."
    cleanup_inspector_containers
    if [[ $# -eq 0 ]]; then
        cleanup_main_container
    fi
    echo ""

    # Summary
    echo "========================================================================"
    echo "  SCENARIO SUMMARY"
    echo "========================================================================"
    for r in "${SCENARIO_RESULTS[@]}"; do
        echo "  $r"
    done
    echo "========================================================================"
    echo "  Log saved to: $LOGFILE"
    echo "========================================================================"
}

main "$@" 2>&1 | tee "$LOGFILE"
