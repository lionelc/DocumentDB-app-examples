---
title: Docker Daemon Availability
impact: CRITICAL
impactDescription: blocks all subsequent checks if Docker is unavailable
tags: [check, docker, prerequisite, infrastructure]
---

## Docker Daemon Availability

The inspector verifies that the Docker CLI is installed and the Docker daemon is running. This is a prerequisite for all container-based checks — if Docker is unavailable, no further inspection can proceed.

**Symptom (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass
ERROR: Docker available  (DOCKER_NOT_FOUND)
  Docker daemon is not running or not accessible

  How to fix:
    1. Start Docker daemon:  sudo systemctl start docker
    2. Install Docker:       https://docs.docker.com/get-docker/
```

**Resolution (Correct state):**

```bash
# Linux — start the daemon
sudo systemctl start docker

# macOS / Windows — open Docker Desktop

# Verify Docker is running
docker info
```

The check runs `command -v docker` to verify the CLI exists, then `docker info` to confirm the daemon is responsive. Both must succeed for the check to pass.

**Error code:** `DOCKER_NOT_FOUND`

**Reference:** [Docker installation guide](https://docs.docker.com/get-docker/)
