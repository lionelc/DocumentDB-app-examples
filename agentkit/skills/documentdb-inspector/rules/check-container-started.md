---
title: Container Startup Verification
impact: CRITICAL
impactDescription: no diagnostics possible if the container fails to start
tags: [check, docker, container, port, startup]
---

## Container Startup Verification

The inspector either verifies an existing container is running (`--container NAME`) or starts a new one. When starting fresh, it first checks that the target host port is free, then runs `docker run` and polls until the container accepts connections.

A `PORT_IN_USE` finding means the inspector **successfully detected** that another process occupies the requested port. This is a diagnostic finding, not an inspector failure — the inspector is working as intended by surfacing the conflict before Docker attempts to bind.

**Symptom — Port conflict (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass --port 10260
ERROR: Container started  (PORT_IN_USE)
  Port 10260 is already in use on the host

  How to fix:
    1. Find occupant:  ss -tlnp | grep 10260
    2. Free the port or re-run with --port <other>
```

**Symptom — Container crash (Incorrect state):**

```
ERROR: Container started  (CONTAINER_FAILED)
  Container exited unexpectedly. Logs: ...
```

**Resolution (Correct state):**

```bash
# Free the port
ss -tlnp | grep 10260
# Stop the conflicting process, then re-run

# Or use a different port
documentdb-inspector.sh --password mypass --port 10261

# Start DocumentDB correctly
docker run -dt -p 10260:10260 --name my-docdb \
  ghcr.io/documentdb/documentdb/documentdb-local:latest \
  --username docdbadmin --password mypass
```

The inspector maps `HOST_PORT:10260` (DocumentDB's internal port is always 10260). It polls with `mongosh` ping commands until the container responds, up to `--timeout` seconds.

**Error codes:** `PORT_IN_USE`, `CONTAINER_FAILED`

**Reference:** [DocumentDB README — Docker setup](https://github.com/documentdb/documentdb#get-started)
