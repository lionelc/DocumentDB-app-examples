# DocumentDB Inspector — Rules Reference

**Version 1.0.0**
DocumentDB Agent Kit
April 2026

> **Note:**
> This document is primarily for agents and LLMs to follow when diagnosing,
> setting up, or troubleshooting DocumentDB local containers.

---

## Abstract

Health-check and diagnostic tool for DocumentDB local Docker containers. Provides automated checks for Docker availability, image management, container lifecycle, port reachability, TLS configuration, and CRUD operations, with actionable error codes and fix suggestions.

---

## Table of Contents

1. [Diagnostic Checks](#1-diagnostic-checks) — **CRITICAL–HIGH**
   - 1.1 [Container Startup Verification](#11-container-startup-verification)
   - 1.2 [CRUD Smoke Test](#12-crud-smoke-test)
   - 1.3 [Docker Daemon Availability](#13-docker-daemon-availability)
   - 1.4 [Image Pull Verification](#14-image-pull-verification)
   - 1.5 [Port Reachability](#15-port-reachability)
   - 1.6 [TLS Handshake Validation](#16-tls-handshake-validation)
2. [Setup Procedures](#2-setup-procedures) — **MEDIUM**
   - 2.1 [Setup DocumentDB from Scratch](#21-setup-documentdb-from-scratch)
   - 2.2 [Load Sample Data](#22-load-sample-data)
3. [Benchmarking & Comparison](#3-benchmarking-comparison) — **MEDIUM**
   - 3.1 [Benchmark DocumentDB vs MongoDB](#31-benchmark-documentdb-vs-mongodb)
4. [Testing & Validation](#4-testing-validation) — **MEDIUM**
   - 4.1 [Run Compatibility Tests](#41-run-compatibility-tests)

---

## 1. Diagnostic Checks

**Impact: CRITICAL–HIGH**

### 1.1 Container Startup Verification

**Impact: CRITICAL** (no diagnostics possible if the container fails to start)

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

### 1.2 CRUD Smoke Test

**Impact: HIGH** (verifies end-to-end data path including authentication)

## CRUD Smoke Test

The inspector runs a full Create → Read → Update → Read → Delete cycle using `mongosh` against a temporary database (`__inspector_test`). This validates authentication, authorization, and basic data operations.

**Symptom — Authentication failure (Incorrect state):**

```
$ documentdb-inspector.sh --password WRONG --container my-docdb --tls required
ERROR: Smoke test (CRUD)  (AUTH_FAILED)
  MongoServerError: Invalid key

  How to fix:
    1. Verify --user / --password match container credentials
    2. Remove container & volume, then recreate if credentials changed
```

**Symptom — CRUD failure (Incorrect state):**

```
ERROR: Smoke test (CRUD)  (CRUD_FAILED)
  Error: INSERT failed

  How to fix:
    1. docker logs <container>
    2. Verify instance finished initialising
    3. Try connecting manually with mongosh
```

**Resolution (Correct state):**

```bash
# Ensure credentials match what was used to create the container
docker run -dt -p 10260:10260 --name my-docdb \
  ghcr.io/documentdb/documentdb/documentdb-local:latest \
  --username docdbadmin --password mypass

# Connect and verify manually
mongosh "mongodb://docdbadmin:mypass@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true" \
  --eval "db.runCommand({ping:1})"
```

The smoke test creates a temporary collection, inserts a document, reads it back, updates a field, verifies the update, deletes the document, and drops the test database. The test database `__inspector_test` is fully cleaned up on both success and failure.

**Error codes:** `AUTH_FAILED`, `CRUD_FAILED`

**Note:** DocumentDB returns `MongoServerError: Invalid key` for authentication failures (differs from standard MongoDB's `Authentication failed` message).

### 1.3 Docker Daemon Availability

**Impact: CRITICAL** (blocks all subsequent checks if Docker is unavailable)

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

### 1.4 Image Pull Verification

**Impact: CRITICAL** (container cannot start without the image available locally)

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

### 1.5 Port Reachability

**Impact: HIGH** (unreachable port prevents all client connections)

## Port Reachability

The inspector tests that the DocumentDB container port is reachable via TCP. This check succeeds if a TCP connection can be established within 10 seconds.

**Symptom (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass --port 10260 --check-only
ERROR: Port reachable  (PORT_UNREACHABLE)
  Cannot reach localhost:10260
```

**Resolution (Correct state):**

```bash
# Verify the container is running
docker ps --filter "name=my-docdb"

# Check from the host
timeout 5 bash -c 'echo > /dev/tcp/localhost/10260' && echo "reachable" || echo "unreachable"

# If using Docker Desktop, ensure port forwarding is active
# If using a remote host, check firewall rules
```

The check uses bash's built-in `/dev/tcp` pseudo-device for a lightweight TCP probe without requiring additional tools.

**Error code:** `PORT_UNREACHABLE`

### 1.6 TLS Handshake Validation

**Impact: HIGH** (TLS misconfiguration blocks all secure client connections)

## TLS Handshake Validation

The inspector validates TLS negotiation using `openssl s_client`. DocumentDB local enables TLS by default with self-signed certificates. This check is skipped when `--tls off` is used.

**Symptom (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass --tls required --check-only --port 10271
ERROR: TLS handshake  (TLS_HANDSHAKE_FAILED)
  TLS handshake failed. error:0A00010B:SSL routines:ssl3_get_record:wrong version number

  How to fix:
    1. Re-run with --tls off or --tls prefer
    2. Ensure the container was started with TLS support
    3. For dev use, --tls off is acceptable
```

**Resolution (Correct state):**

```bash
# DocumentDB local has TLS enabled by default
# Connect with TLS (allow self-signed certs):
mongosh "mongodb://docdbadmin:mypass@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true"

# If TLS is not needed for development:
documentdb-inspector.sh --password mypass --tls off

# The "wrong version number" error means the server is NOT speaking TLS
# This happens when connecting to a non-TLS service with --tls required
```

The check runs `echo | openssl s_client -connect localhost:PORT` and looks for `BEGIN CERTIFICATE` in the output. With `--tls prefer`, a failed handshake falls back to plain text instead of failing.

**Error code:** `TLS_HANDSHAKE_FAILED`

**Reference:** [DocumentDB TLS configuration](https://github.com/documentdb/documentdb)

---

## 2. Setup Procedures

**Impact: MEDIUM**

### 2.1 Setup DocumentDB from Scratch

**Impact: MEDIUM** (provides step-by-step container provisioning guidance)

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

### 2.2 Load Sample Data

**Impact: MEDIUM** (provides ready-made datasets for development and testing)

## Load Sample Data

Downloads and loads the official DocumentDB sample datasets into the `sampledb` database. The data represents a simple e-commerce application with users, products, orders, and analytics.

**Symptom (Incorrect state — empty database):**

```js
use("sampledb");
db.getCollectionNames();
// []  — no collections
```

**Resolution (Correct state):**

```bash
# Download sample data scripts
curl -sLO https://raw.githubusercontent.com/documentdb/documentdb/main/sample-data/01-users.js
curl -sLO https://raw.githubusercontent.com/documentdb/documentdb/main/sample-data/02-products.js
curl -sLO https://raw.githubusercontent.com/documentdb/documentdb/main/sample-data/03-orders.js
curl -sLO https://raw.githubusercontent.com/documentdb/documentdb/main/sample-data/04-analytics.js

# Load into DocumentDB
CONN="mongodb://docdbadmin:mypass@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true"
mongosh "$CONN" --quiet --file 01-users.js
mongosh "$CONN" --quiet --file 02-products.js
mongosh "$CONN" --quiet --file 03-orders.js
mongosh "$CONN" --quiet --file 04-analytics.js
```

**What gets loaded:**

| Collection | Records | Description |
|------------|---------|-------------|
| `users` | 5 | User profiles with preferences, tags, and indexed fields |
| `products` | 5 | Product catalog with specs, pricing, and ratings |
| `orders` | 4 | Orders in various stages with line items and shipping |
| `analytics` | 2 | Monthly summaries and daily activity logs |

**Tip:** If the container was started *without* `--skip-init-data`, the sample data is loaded automatically on first boot.

**Reference:** [DocumentDB sample-data](https://github.com/documentdb/documentdb/tree/main/sample-data)

---

## 3. Benchmarking & Comparison

**Impact: MEDIUM**

### 3.1 Benchmark DocumentDB vs MongoDB

**Impact: MEDIUM** (measures query performance and correctness against native MongoDB)

## Benchmark DocumentDB vs MongoDB

Runs identical queries against both DocumentDB and MongoDB to compare performance (timing) and correctness (result matching). Covers simple filters, aggregations, multi-collection `$lookup` joins, and complex computed pipelines.

**Symptom (Incorrect state — no benchmark data available):**

```
User: "Is DocumentDB as fast as MongoDB?"
User: "Do my queries produce the same results on both engines?"
# No data to answer — need to run the benchmark
```

**Resolution (Correct state — run the comparison benchmark):**

```bash
# Run the full benchmark (11 queries, side-by-side timing + correctness check)
bash testing/scenarios/01-load-sample-data/compare_run.sh
```

**What it does:**

1. Ensures a DocumentDB container is running with sample data loaded
2. Runs 11 benchmark queries against DocumentDB, recording timing and output
3. Stops DocumentDB, starts a MongoDB 8.0 container on the same port
4. Loads the same sample data into MongoDB
5. Runs the identical 11 queries against MongoDB
6. Stops MongoDB, restarts DocumentDB
7. Prints a side-by-side timing comparison table
8. Compares every query's output line-by-line and reports whether results are identical or differ

**Benchmark queries included:**

| # | Query | Type |
|---|-------|------|
| Q1 | Users in San Francisco | Single-collection filter |
| Q2 | Products under $100 | Sort by nested field |
| Q3 | Orders shipped/delivered | `$in` filter |
| Q4 | Customer order history | `$lookup` (orders → users) |
| Q5 | Line items + product details | `$unwind` + `$lookup` |
| Q6 | Revenue by city | `$lookup` + `$group` |
| Q7 | Top customers by spending | `$group` + `$lookup` |
| Q8 | Most ordered products | `$unwind` + `$group` + `$lookup` |
| Q9 | Full order invoice | Triple join (orders → users → products) |
| Q10 | User activity feed | 4-way join (analytics → users → products → orders) |
| Q11 | Customer lifetime value | 3-way join with `$sortArray`, `$addFields`, computed metrics |

**Example output:**

```
  BENCHMARK RESULTS: DocumentDB vs MongoDB

  Query                            DocumentDB    MongoDB       Diff
  ────────────────────────────────────────────────────────────────
  Users in SF (filter)                  735 ms      524 ms    +211 ms
  Full invoice (triple join)            779 ms      561 ms    +218 ms
  Customer LTV (3-join+compute)         785 ms      564 ms    +221 ms
  ...

  RESULTS CORRECTNESS CHECK
  Q1–Q10  ✅ Results are identical
  Q11     ❌ Results DIFFER (tie-breaking order in $setUnion)
```

**Reference:** [DocumentDB vs MongoDB compatibility](https://github.com/documentdb/documentdb)

---

## 4. Testing & Validation

**Impact: MEDIUM**

### 4.1 Run Compatibility Tests

**Impact: MEDIUM** (validates DocumentDB compatibility using the official functional test suite)

## Run Compatibility Tests

Downloads and runs the official [documentdb/functional-tests](https://github.com/documentdb/functional-tests) pytest suite against a live DocumentDB container. This tests real MongoDB API compatibility across find, insert, aggregation, and collection operations.

**Symptom (Incorrect state — compatibility unknown):**

```
User: "Does DocumentDB pass the official compatibility tests?"
User: "Are there any MongoDB features that don't work in DocumentDB?"
# No test results available — need to run the suite
```

**Resolution (Correct state — run the compatibility tests):**

```bash
# Run the full functional test suite (downloads tests on demand)
bash testing/scenarios/11-compatibility-tests/run.sh
```

**What it does:**

1. Ensures a DocumentDB container is running
2. Clones `documentdb/functional-tests` from GitHub (shallow clone, cleaned up after)
3. Creates a Python virtual environment and installs test dependencies
4. Runs the pytest suite against DocumentDB with `--engine-name documentdb`
5. Produces a JSON report and prints a summary with pass/fail counts
6. Highlights specific test failures — these indicate DocumentDB compatibility gaps

**Example output:**

```
  Total:    59
  Passed:   57
  Failed:   2

  Failed tests:
    test_create_capped_collection — Capped collections not supported
    test_find_invalid_collection  — DocumentDB accepts names MongoDB rejects
```

**Reference:** [documentdb/functional-tests](https://github.com/documentdb/functional-tests)

---

## References

- [DocumentDB GitHub repository](https://github.com/documentdb/documentdb)
- [DocumentDB documentation](https://documentdb.io/docs)
- [DocumentDB sample data](https://github.com/documentdb/documentdb/tree/main/sample-data)
