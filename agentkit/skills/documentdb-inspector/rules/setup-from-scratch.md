---
title: Setup DocumentDB from Scratch
impact: MEDIUM
impactDescription: provides step-by-step container provisioning guidance
tags: [setup, docker, container, getting-started]
---

## Setup DocumentDB from Scratch

Walks through the full container lifecycle: pull the official image, start a container with credentials and port mapping, and verify health with the inspector.

**Symptom (Incorrect state — no container running):**

```
$ docker ps --filter "name=documentdb"
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
# (empty — no DocumentDB container)
```

**Resolution (Correct state):**

```bash
# 1. Pull the official image
docker pull ghcr.io/documentdb/documentdb/documentdb-local:latest

# 2. Start the container
docker run -dt \
  -p 10260:10260 \
  --name documentdb-local \
  ghcr.io/documentdb/documentdb/documentdb-local:latest \
  --username docdbadmin \
  --password YourPassword123

# 3. Wait for readiness (watch for "waiting for connections")
docker logs -f documentdb-local

# 4. Verify with the inspector
documentdb-inspector.sh --password YourPassword123 --port 10260 \
  --container documentdb-local --tls required

# 5. Connect with mongosh
mongosh "mongodb://docdbadmin:YourPassword123@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true"
```

**Key details:**
- The container internal port is always `10260` (not MongoDB's default `27017`)
- Credentials are passed as `--username` / `--password` flags (not environment variables)
- TLS is enabled by default with self-signed certificates
- Use `--skip-init-data` to prevent automatic sample data loading

**Reference:** [DocumentDB README](https://github.com/documentdb/documentdb#get-started)
