---
name: documentdb-inspector
description: |
  DocumentDB local container health-check, diagnostic, benchmarking, and compatibility
  testing tool. Use when setting up, verifying, troubleshooting, benchmarking, or
  testing a DocumentDB local Docker instance.
license: MIT
metadata:
  author: documentdb-agent-kit
  version: "1.0.0"
---

# DocumentDB Inspector

Health-check, diagnostic, and benchmarking tool for DocumentDB local containers, containing 10 rules across 4 categories, prioritized by impact.

## When to Apply

Reference these guidelines when:
- Setting up a new DocumentDB local container from scratch
- Checking whether a running DocumentDB instance is healthy
- Diagnosing connection, TLS, or authentication failures
- Running pre-flight checks before compatibility tests
- Loading sample data for development or testing
- Benchmarking DocumentDB query performance against MongoDB
- Checking if DocumentDB produces the same results as MongoDB
- Running the official compatibility/functional test suite
- Using DocumentDB in a CI/CD pipeline

## Common User Prompts → Scenarios

Use this mapping to determine which scenario to run based on what the user asks:

| User says… | Run this |
|------------|----------|
| "Help me set up DocumentDB locally" | `bash testing/scenarios/00-start-from-scratch/run.sh` |
| "Load some sample data so I can play around" | `bash testing/scenarios/01-load-sample-data/run.sh` |
| "Is my DocumentDB healthy?" / "Check my container" | `bash testing/scenarios/02-happy-path/run.sh` |
| "Docker doesn't seem to be working" | `bash testing/scenarios/03-docker-not-running/run.sh` |
| "Something is using my port" / "Port conflict" | `bash testing/scenarios/04-port-conflict/run.sh` |
| "TLS isn't working" / "Can't connect with TLS" | `bash testing/scenarios/05-tls-handshake-failure/run.sh` |
| "Authentication failed" / "Wrong password" | `bash testing/scenarios/06-auth-failure/run.sh` |
| "Can't pull the image" / "Network issue" | `bash testing/scenarios/07-image-pull-failure/run.sh` |
| "Run the doctor but keep the container" | `bash testing/scenarios/08-keep-container/run.sh` |
| "Test with a specific version" | `bash testing/scenarios/09-custom-image-tag/run.sh` |
| "Run a pre-flight check before my tests" | `bash testing/scenarios/10-programmatic-invocation/run.sh` |
| "Run the compatibility tests" / "Does DocumentDB pass the functional tests?" | `bash testing/scenarios/11-compatibility-tests/run.sh` |
| "How fast is DocumentDB?" / "Compare DocumentDB to MongoDB" | `bash testing/scenarios/01-load-sample-data/compare_run.sh` |
| "Do queries produce the same results as MongoDB?" | `bash testing/scenarios/01-load-sample-data/compare_run.sh` |
| "Benchmark DocumentDB" / "Performance comparison" | `bash testing/scenarios/01-load-sample-data/compare_run.sh` |

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | Diagnostic Checks | CRITICAL–HIGH | `check-` |
| 2 | Setup Procedures | MEDIUM | `setup-` |
| 3 | Benchmarking & Comparison | MEDIUM | `benchmark-` |
| 4 | Testing & Validation | MEDIUM | `testing-` |

## Quick Reference

### 1. Diagnostic Checks (CRITICAL–HIGH)

- [check-docker-available](rules/check-docker-available.md) — Verify Docker daemon is running
- [check-image-pulled](rules/check-image-pulled.md) — Ensure DocumentDB image is available locally
- [check-container-started](rules/check-container-started.md) — Verify container started without port conflicts
- [check-port-reachable](rules/check-port-reachable.md) — Confirm the container port accepts TCP connections
- [check-tls-handshake](rules/check-tls-handshake.md) — Validate TLS negotiation with the container
- [check-crud-smoke-test](rules/check-crud-smoke-test.md) — Run insert/read/update/delete operations

### 2. Setup Procedures (MEDIUM)

- [setup-from-scratch](rules/setup-from-scratch.md) — Pull image, create container, verify health
- [setup-load-sample-data](rules/setup-load-sample-data.md) — Load official sample datasets and run queries

### 3. Benchmarking & Comparison (MEDIUM)

- [benchmark-compare-mongodb](rules/benchmark-compare-mongodb.md) — Performance and correctness comparison vs MongoDB

### 4. Testing & Validation (MEDIUM)

- [testing-compatibility-tests](rules/testing-compatibility-tests.md) — Run official functional test suite

## Inspector Tool

The skill includes an executable inspector script:

```bash
./documentdb-inspector.sh --password <pass> [OPTIONS]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--image IMAGE` | Docker image | `ghcr.io/documentdb/documentdb/documentdb-local:latest` |
| `--port PORT` | Host port | `10260` |
| `--user USER` | Username | `docdbadmin` |
| `--password PASS` | Password | *(required)* |
| `--tls MODE` | `required` / `prefer` / `off` | `off` |
| `--timeout SECS` | Startup timeout | `120` |
| `--keep` | Leave container running | `false` |
| `--container NAME` | Inspect existing container | — |
| `--check-only` | Skip Docker/image/container | `false` |
| `--json` | JSON-only output | `false` |
| `--report FILE` | Save JSON report | — |

## Error Codes

| Code | Check | Meaning |
|------|-------|---------|
| `DOCKER_NOT_FOUND` | Docker available | Docker CLI missing or daemon stopped |
| `IMAGE_PULL_FAILED` | Image pulled | Network/registry issue pulling image |
| `PORT_IN_USE` | Container started | Host port already bound |
| `CONTAINER_FAILED` | Container started | Container crashed or timed out |
| `PORT_UNREACHABLE` | Port reachable | TCP connection refused |
| `TLS_HANDSHAKE_FAILED` | TLS handshake | TLS negotiation rejected |
| `AUTH_FAILED` | Smoke test (CRUD) | Wrong credentials |
| `CRUD_FAILED` | Smoke test (CRUD) | Insert/read/update/delete failure |

## How to Use

Use the linked rule files above for detailed explanations. Each rule file contains:
- Brief explanation of what the check does
- Symptom — what the error looks like
- Resolution — how to fix it
- Additional context and references

## Full Compiled Document

For the complete guide with all rules expanded: [AGENTS.md](AGENTS.md)
