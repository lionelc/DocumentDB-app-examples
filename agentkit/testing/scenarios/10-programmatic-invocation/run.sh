#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 10 "Agent-to-Agent Invocation (Programmatic)"

ensure_main_container || { echo "SKIP: container unavailable"; exit 1; }
json_file=$(mktemp)
trap "rm -f $json_file" EXIT

echo "--- Step 1: Run inspector with --json --report ---"
"$INSPECTOR" --password "$PASSWORD" --port "$MAIN_PORT" \
    --container "$MAIN_CONTAINER" --tls required \
    --json --report "$json_file" > /dev/null 2>&1
echo ""

echo "--- Step 2: JSON report contents ---"
cat "$json_file"
echo ""

echo "--- Step 3: Programmatic decision based on JSON ---"
python3 - "$json_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)

print(f"Overall status: {data['overallStatus']}")
print(f"Checks run: {len(data['checks'])}")
for c in data["checks"]:
    symbol = "PASS" if c["status"] in ("PASS","SKIP") else "FAIL"
    print(f"  [{symbol}] {c['name']:<25} {c['durationMs']:>5} ms  {c.get('errorCode','')}")

print()
if data["overallStatus"] == "PASS":
    print("Decision: System is healthy. Proceeding to integration tests...")
else:
    print("Decision: System is NOT healthy. Skipping integration tests.")
    for c in data["checks"]:
        if c["status"] == "FAIL":
            print(f"  Root cause: {c['errorCode']} - {c['error'][:120]}")
PYEOF
