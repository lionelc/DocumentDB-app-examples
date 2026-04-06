# Scenario: Docker Not Running

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Simulate Docker being unavailable by pointing `DOCKER_HOST` at a non-existent socket.
The inspector should detect the missing Docker daemon on its first check and report
`DOCKER_NOT_FOUND`.

## Prerequisites

- Docker installed (binary present, but we make the daemon unreachable)
- mongosh available on PATH

## Setup Steps

```bash
# Point Docker CLI at a socket that does not exist.
# This makes `docker info` fail without actually stopping the daemon.
export DOCKER_HOST=unix:///var/run/docker-nonexistent.sock
```

## Inspector Command

```bash
DOCKER_HOST=unix:///var/run/docker-nonexistent.sock \
documentdb-inspector.sh --password Test1234
```

## Expected Outcome

| Check              | Expected Status | Error Code        |
|--------------------|----------------|-------------------|
| Docker available   | FAIL           | DOCKER_NOT_FOUND  |
| Image pulled       | *(not run)*    |                   |
| Container started  | *(not run)*    |                   |
| Port reachable     | *(not run)*    |                   |
| TLS handshake      | *(not run)*    |                   |
| Smoke test (CRUD)  | *(not run)*    |                   |

## Success Criteria

- [ ] Inspector detects that Docker is unreachable
- [ ] Error code `DOCKER_NOT_FOUND` is reported for "Docker available"
- [ ] Subsequent checks are skipped (inspector exits early after Docker check fails)
- [ ] Output includes a "How to fix" hint mentioning `systemctl start docker`
- [ ] Overall status is `FAIL`
- [ ] Exit code is non-zero

## Notes

- We use `DOCKER_HOST` redirection rather than stopping the real Docker daemon so that
  other containers and parallel tests are not disrupted.
- The inspector calls `docker info` to verify daemon availability; the fake socket makes
  this fail immediately.
