---
title: Run Compatibility Tests
impact: MEDIUM
impactDescription: validates DocumentDB compatibility using the official functional test suite
tags: [testing, integration, compatibility, functional-tests, pytest]
---

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
