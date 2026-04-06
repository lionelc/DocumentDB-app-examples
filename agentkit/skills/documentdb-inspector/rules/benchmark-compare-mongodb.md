---
title: Benchmark DocumentDB vs MongoDB
impact: MEDIUM
impactDescription: measures query performance and correctness against native MongoDB
tags: [benchmark, comparison, mongodb, performance, compatibility]
---

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
