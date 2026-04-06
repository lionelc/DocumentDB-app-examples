# Scenario: Start from Scratch

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Verify that the inspector can pull the DocumentDB Docker image from scratch, start a
new container, and confirm the instance is healthy — simulating a first-time setup on a
clean machine.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- Network access to `ghcr.io` (to pull the image)

## Setup Steps

```bash
# Remove any leftover inspector containers and the cached image
docker rm -f $(docker ps -aq --filter "name=documentdb-inspector") 2>/dev/null || true
docker rmi ghcr.io/documentdb/documentdb/documentdb-local:latest 2>/dev/null || true
```

## Inspector Command

```bash
documentdb-inspector.sh --password Test1234
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

- [ ] Image is pulled from the registry (not cached)
- [ ] Container starts and becomes healthy within the default 120 s timeout
- [ ] Port 10260 is reachable on localhost
- [ ] CRUD smoke test inserts, reads, updates, and deletes successfully
- [ ] Overall status is `PASS`
- [ ] Container is cleaned up after the run (no `--keep`)

## Notes

- TLS handshake is expected to be `SKIP` because `--tls` defaults to `off`.
- This is typically the slowest scenario because it includes the image pull.
- The container maps host port 10260 → container port 10260 by default.
