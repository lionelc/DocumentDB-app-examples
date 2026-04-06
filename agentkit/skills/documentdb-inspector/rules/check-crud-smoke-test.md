---
title: CRUD Smoke Test
impact: HIGH
impactDescription: verifies end-to-end data path including authentication
tags: [check, crud, auth, mongosh, smoke-test]
---

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
