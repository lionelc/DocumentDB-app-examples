# Scenario: Load Sample Data

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Verify that official sample datasets can be loaded into a running DocumentDB container.
This scenario depends on a healthy container already being available (started by
scenario 00 or via `ensure_main_container` in the test harness).

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- DocumentDB container running on port 10260 with user `docdbadmin` / password `Test1234`
- Sample dataset files or mongosh scripts available

## Setup Steps

```bash
# Ensure the main test container is running
source testing/harness/helpers.sh
ensure_main_container

# Verify connectivity before loading data
mongosh "mongodb://docdbadmin:Test1234@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true&directConnection=true" \
  --quiet --eval "db.runCommand({ping:1})"
```

## Inspector Command

```bash
# Run inspector against the existing container to confirm health before/after load
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

- [ ] Container is confirmed running via `--container` flag (image pull is skipped)
- [ ] Port 10260 is reachable
- [ ] CRUD smoke test passes after sample data is loaded
- [ ] Sample collections are queryable via mongosh
- [ ] Overall status is `PASS`

## Notes

- The `--container` flag tells the inspector to use an existing container, skipping
  image pull and container creation.
- Image pulled shows `SKIP` because the inspector skips the pull check when
  `--container` is specified.
- Sample data loading is an external step; the inspector only validates that the
  instance remains healthy afterward.
