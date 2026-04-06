# Scenario: Happy Path

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Run the inspector against a fully healthy DocumentDB container and verify that every
check passes. This is the baseline "golden path" — no faults injected, no edge cases.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
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
  --port 10260
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

## Success Criteria

- [ ] All six checks complete
- [ ] Docker available, Container started, Port reachable, and Smoke test all report `PASS`
- [ ] TLS handshake is `SKIP` (TLS mode defaults to `off`)
- [ ] Image pulled is `SKIP` (using `--container` mode)
- [ ] Overall status is `PASS`
- [ ] Exit code is 0

## Notes

- This scenario exists to confirm that the inspector produces a clean report when
  everything is working. It serves as the control for comparison with fault-injection
  scenarios.
- Uses `--container` to point at the shared test container rather than creating a new one.
