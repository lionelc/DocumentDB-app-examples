# Scenario: Authentication Failure

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Run the inspector against a healthy DocumentDB container but supply the wrong password.
All infrastructure checks should pass, but the CRUD smoke test should fail with
`AUTH_FAILED` because mongosh cannot authenticate.

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
  --password WrongPassword999 \
  --container documentdb-test-main \
  --port 10260
```

## Expected Outcome

| Check              | Expected Status | Error Code   |
|--------------------|----------------|--------------|
| Docker available   | PASS           |              |
| Image pulled       | SKIP           |              |
| Container started  | PASS           |              |
| Port reachable     | PASS           |              |
| TLS handshake      | SKIP           |              |
| Smoke test (CRUD)  | FAIL           | AUTH_FAILED  |

## Success Criteria

- [ ] Docker available, Container started, and Port reachable all pass
- [ ] Smoke test (CRUD) fails with error code `AUTH_FAILED`
- [ ] Error output contains "authentication failed" or similar mongosh error text
- [ ] "How to fix" hint suggests verifying `--user` / `--password`
- [ ] Overall status is `FAIL`
- [ ] Exit code is non-zero

## Notes

- The correct password for the test container is `Test1234`. This scenario deliberately
  provides `WrongPassword999` to trigger the auth failure path.
- The inspector distinguishes `AUTH_FAILED` from `CRUD_FAILED` by pattern-matching
  mongosh output for authentication-related error messages (e.g., `AuthenticationFailed`,
  `SCRAM`, `Invalid key`).
- TLS handshake is `SKIP` because TLS mode defaults to `off`.
