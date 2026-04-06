---
title: Image Pull Verification
impact: CRITICAL
impactDescription: container cannot start without the image available locally
tags: [check, docker, image, network]
---

## Image Pull Verification

The inspector checks whether the DocumentDB Docker image is available locally. If not cached, it attempts a `docker pull`. This check fails on air-gapped networks or behind corporate proxies that block container registries.

**Symptom (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass --image ghcr.io/documentdb/documentdb/documentdb-local:latest
ERROR: Image pulled  (IMAGE_PULL_FAILED)
  Error response from daemon: Get https://ghcr.io/v2/: net/http: request canceled

  How to fix:
    1. Check network / proxy settings
    2. Pull manually:  docker pull ghcr.io/documentdb/documentdb/documentdb-local:latest
    3. Air-gapped env: docker save / docker load
```

**Resolution (Correct state):**

```bash
# Pull the image
docker pull ghcr.io/documentdb/documentdb/documentdb-local:latest

# Behind a proxy — configure Docker's proxy
# See: https://docs.docker.com/network/proxy/

# Air-gapped — transfer via tarball
docker save ghcr.io/documentdb/documentdb/documentdb-local:latest -o documentdb.tar
# On target machine:
docker load -i documentdb.tar
```

The check first runs `docker image inspect` to see if the image is cached. If cached, the check passes instantly. Otherwise it attempts `docker pull` and reports the pull output on failure.

**Error code:** `IMAGE_PULL_FAILED`

**Reference:** [DocumentDB Docker image](https://github.com/documentdb/documentdb)
