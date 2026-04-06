# Scenario: Programmatic Invocation

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Run the inspector with `--json` output and verify the result can be parsed
programmatically. This validates the machine-readable interface that CI pipelines and
agent-kit integrations rely on.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- `python3` available on PATH (used to validate JSON)
- `jq` available on PATH (optional, used for field assertions)
- DocumentDB container running on port 10260 with user `docdbadmin` / password `Test1234`

## Setup Steps

```bash
# Ensure the main test container is running and healthy
source testing/harness/helpers.sh
ensure_main_container
cleanup_inspector_containers
```

## Inspector Command

```bash
documentdb-inspector.sh \
  --password Test1234 \
  --container documentdb-test-main \
  --port 10260 \
  --json
```

## Expected Outcome

| Check              | Expected Status | Error Code |
|--------------------|----------------|------------|
| Docker available   | PASS           |            |
| Image pulled       | SKIP           |            |
| Container started  | PASS           |            |
| Port reachable     | PASS           |            |
| TLS handshake      | SKIP           |            |
| Smoke test (CRUD)  | PASS           |            |

### Expected JSON Structure

```json
{
  "overallStatus": "PASS",
  "image": "ghcr.io/documentdb/documentdb/documentdb-local:latest",
  "port": 10260,
  "tlsMode": "off",
  "container": "documentdb-test-main",
  "checks": [
    { "name": "Docker available",  "status": "PASS", "durationMs": ..., "errorCode": "", "error": "" },
    { "name": "Image pulled",      "status": "SKIP", "durationMs": 0,   "errorCode": "", "error": "" },
    { "name": "Container started", "status": "PASS", "durationMs": ..., "errorCode": "", "error": "" },
    { "name": "Port reachable",    "status": "PASS", "durationMs": ..., "errorCode": "", "error": "" },
    { "name": "TLS handshake",     "status": "SKIP", "durationMs": 0,   "errorCode": "", "error": "" },
    { "name": "Smoke test (CRUD)", "status": "PASS", "durationMs": ..., "errorCode": "", "error": "" }
  ]
}
```

## Success Criteria

- [ ] `--json` flag suppresses the human-readable table (no table on stdout)
- [ ] stdout contains valid JSON (parseable by `python3 -m json.tool`)
- [ ] Top-level field `overallStatus` equals `"PASS"`
- [ ] Top-level field `port` is the integer `10260`
- [ ] Top-level field `tlsMode` equals `"off"`
- [ ] Top-level field `container` equals `"documentdb-test-main"`
- [ ] `checks` array has 6 elements
- [ ] Each check object has fields: `name`, `status`, `durationMs`, `errorCode`, `error`
- [ ] `durationMs` values are non-negative integers
- [ ] Exit code is 0

### Validation Commands

```bash
# Parse and assert with jq
OUTPUT=$(documentdb-inspector.sh --password Test1234 --container documentdb-test-main --port 10260 --json)
echo "$OUTPUT" | python3 -m json.tool > /dev/null            # valid JSON
echo "$OUTPUT" | jq -e '.overallStatus == "PASS"'            # overall pass
echo "$OUTPUT" | jq -e '.checks | length == 6'               # six checks
echo "$OUTPUT" | jq -e '.port == 10260'                      # correct port
echo "$OUTPUT" | jq -e '[.checks[].durationMs] | all(. >= 0)' # non-negative durations
```

## Notes

- The `--json` flag outputs JSON to stdout; log messages still go to stderr.
- The `--report FILE` flag can be combined with or used instead of `--json` to write the
  JSON to a file — this scenario focuses on stdout output.
- CI pipelines should use `--json` and parse the output to make pass/fail decisions
  programmatically rather than scraping the human-readable table.
