---
title: Load Sample Data
impact: MEDIUM
impactDescription: provides ready-made datasets for development and testing
tags: [setup, sample-data, mongosh, development]
---

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
