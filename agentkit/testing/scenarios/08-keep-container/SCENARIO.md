# Scenario: Keep Container

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Run the inspector with the `--keep` flag and verify that the container is **not**
removed after the inspection completes. By default the inspector cleans up containers
it creates; `--keep` overrides this behaviour.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- DocumentDB image available locally (already pulled)

## Setup Steps

```bash
# Clean up any leftover inspector containers to start fresh
source testing/harness/helpers.sh
cleanup_inspector_containers
```

## Inspector Command

```bash
documentdb-inspector.sh \
  --password Test1234 \
  --keep
```

## Expected Outcome

| Check              | Expected Status | Error Code |
|--------------------|----------------|------------|
| Docker available   | PASS           |            |
| Image pulled       | PASS           |            |
| Container started  | PASS           |            |
| Port reachable     | PASS           |            |
| TLS handshake      | SKIP           |            |
| Smoke test (CRUD)  | PASS           |            |

## Success Criteria

- [ ] All checks pass, overall status is `PASS`
- [ ] After the inspector exits, the container it created is still running (`docker ps` lists it)
- [ ] Output includes the message: "Container '...' left running (--keep)."
- [ ] Output includes a `mongosh` connection string for manual access
- [ ] Output includes a `docker rm -f` cleanup command
- [ ] The container is connectable via mongosh after the inspector finishes

## Teardown

```bash
# Manually clean up the kept container
docker rm -f $(docker ps -aq --filter "name=documentdb-inspector") 2>/dev/null || true
```

## Notes

- The inspector names auto-created containers `documentdb-inspector-<PID>`. The `--keep`
  flag suppresses the cleanup trap that would normally `docker rm -f` this container on
  exit.
- This scenario validates the developer workflow of "inspect, then keep the container
  around for manual debugging."
