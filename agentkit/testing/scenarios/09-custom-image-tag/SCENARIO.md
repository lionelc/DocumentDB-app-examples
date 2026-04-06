# Scenario: Custom Image Tag

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Run the inspector with a specific (non-default) image tag via `--image` and verify that
the correct image is pulled and used. This validates that the `--image` flag is properly
forwarded to `docker pull` and `docker run`.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- Network access to pull the specified image tag

## Setup Steps

```bash
# Clean up any leftover inspector containers
source testing/harness/helpers.sh
cleanup_inspector_containers

# Determine a valid non-latest tag for the DocumentDB image.
# For testing, use the same image re-tagged locally if a specific
# published version is not available:
CUSTOM_TAG="ghcr.io/documentdb/documentdb/documentdb-local:latest"
# If a pinned version exists (e.g. 1.0.0), use that instead:
# CUSTOM_TAG="ghcr.io/documentdb/documentdb/documentdb-local:1.0.0"
```

## Inspector Command

```bash
documentdb-inspector.sh \
  --password Test1234 \
  --image "$CUSTOM_TAG"
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

- [ ] Inspector log output shows the custom image name (e.g., `Image: <custom-tag>`)
- [ ] Image pulled reports `PASS` (either pulled fresh or found cached)
- [ ] Container starts successfully from the specified image
- [ ] All checks pass, overall status is `PASS`
- [ ] Exit code is 0

## Notes

- If no specific versioned tag is published yet, this scenario can be run with
  `latest` to verify the `--image` flag plumbing works — the key assertion is that the
  inspector log line `Image: ...` reflects the value passed via `--image`.
- When a pinned version tag (e.g., `1.0.0`) becomes available, update `CUSTOM_TAG` to
  that value for a more meaningful test.
- To test fully offline, pre-pull the image with `docker pull` and verify the inspector
  reports it as "cached".
