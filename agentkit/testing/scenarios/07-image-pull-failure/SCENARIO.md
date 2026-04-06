# Scenario: Image Pull Failure

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Run the inspector with a non-existent Docker image tag. The image pull should fail,
producing error code `IMAGE_PULL_FAILED`. The inspector should not attempt to start a
container.

## Prerequisites

- Docker installed and running
- Network access (so Docker actually attempts the pull and fails with "not found"
  rather than a network error)

## Setup Steps

```bash
# Clean up any leftover inspector containers
source testing/harness/helpers.sh
cleanup_inspector_containers

# Ensure the bogus image is not cached locally
docker rmi ghcr.io/documentdb/documentdb/documentdb-local:this-tag-does-not-exist-12345 2>/dev/null || true
```

## Inspector Command

```bash
documentdb-inspector.sh \
  --password Test1234 \
  --image ghcr.io/documentdb/documentdb/documentdb-local:this-tag-does-not-exist-12345
```

## Expected Outcome

| Check              | Expected Status | Error Code         |
|--------------------|----------------|--------------------|
| Docker available   | PASS           |                    |
| Image pulled       | FAIL           | IMAGE_PULL_FAILED  |
| Container started  | *(not run)*    |                    |
| Port reachable     | *(not run)*    |                    |
| TLS handshake      | *(not run)*    |                    |
| Smoke test (CRUD)  | *(not run)*    |                    |

## Success Criteria

- [ ] Docker available passes
- [ ] Image pulled fails with error code `IMAGE_PULL_FAILED`
- [ ] Error output includes the failed image name and Docker pull error details
- [ ] Subsequent checks are skipped (inspector exits early after pull failure)
- [ ] "How to fix" hint suggests checking network/proxy and `docker pull` manually
- [ ] Overall status is `FAIL`
- [ ] Exit code is non-zero

## Notes

- The image tag `this-tag-does-not-exist-12345` is intentionally nonsensical to guarantee
  a pull failure.
- The inspector first checks `docker image inspect` for a local cache hit; when that
  misses, it runs `docker pull`, which fails.
- In air-gapped environments, every image pull would fail — the fix hint mentions
  `docker save` / `docker load` as a workaround.
