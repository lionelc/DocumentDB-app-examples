# DocumentDB App Examples

Ready-to-use applications and developer tools for [DocumentDB](https://github.com/documentdb/documentdb) — the open-source, MongoDB-compatible document database built on PostgreSQL.

## What's in This Repo

### 🛒 [E-Commerce Dashboard](ecommerce/README.md)

A full-stack e-commerce analytics dashboard built with Flask and DocumentDB. Demonstrates real-world usage patterns including CRUD operations, aggregation pipelines, multi-collection `$lookup` joins, live data streaming, and data quality monitoring.

**Highlights:**
- Single-page dashboard with live sales, inventory, and customer analytics
- Background data generator simulating real e-commerce activity
- Aggregation pipelines: revenue by category, customer lifetime value, order funnels
- Built-in health monitoring via the DocumentDB Inspector agent-kit (see below)

```bash
cd ecommerce
pip install -r requirements.txt
python app.py
# → http://localhost:5000
```

---

### 🔍 [DocumentDB Agent Kit](agentkit/README.md)

An AI-agent-compatible skill kit for health-checking, diagnosing, benchmarking, and compatibility-testing DocumentDB local containers. Follows the [Agent Skills](https://agentskills.io/) format — works with GitHub Copilot, Claude Code, Gemini CLI, and similar tools.

**Highlights:**
- **Inspector tool** — 6 automated checks: Docker, image, container, port, TLS, CRUD
- **12 runnable scenarios** — setup, diagnostics, benchmarking, compatibility tests
- **DocumentDB vs MongoDB benchmark** — side-by-side timing and result correctness comparison
- **Compatibility test runner** — runs the official [functional-tests](https://github.com/documentdb/functional-tests) suite
- **Rule-based knowledge base** — compiled `AGENTS.md` that any AI agent can read

```bash
cd agentkit
npm install && npm run build

# Run the inspector
bash skills/documentdb-inspector/documentdb-inspector.sh --password Test1234 --port 10260 --tls required

# Run all diagnostic scenarios
bash testing/harness/run-all-scenarios.sh

# Benchmark DocumentDB vs MongoDB
bash testing/scenarios/01-load-sample-data/compare_run.sh

# Run compatibility tests
bash testing/scenarios/11-compatibility-tests/run.sh
```

---

## How They Work Together

The ecommerce app integrates the agent-kit as a **production health monitor**:

```
┌─────────────────────┐         ┌──────────────────────────┐
│   E-Commerce App    │  every  │  DocumentDB Agent Kit    │
│   (Flask + DocDB)   │──hour──▶│  documentdb-inspector.sh │
│                     │         │  --json --report         │
│  /api/health ◀──────│◀────────│  returns JSON report     │
│                     │         └──────────────────────────┘
│  if unhealthy:      │
│    → send alert     │──▶  Email / Slack / PagerDuty
└─────────────────────┘
```

The `health_monitor.py` module in the ecommerce app:
1. Runs `documentdb-inspector.sh --json` every hour in a background thread
2. Parses the structured JSON report
3. Exposes results at `GET /api/health` (200 if healthy, 503 if not)
4. Sends alerts when issues are detected (configurable: email, Slack, PagerDuty)
5. Sends recovery notifications when health returns to normal

**To enable in your own app**, copy `health_monitor.py` and add three lines:

```python
import health_monitor

# In your startup function:
health_monitor.start()

# In your shutdown function:
health_monitor.stop()
```

Configure via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HEALTH_CHECK_INTERVAL` | `3600` | Seconds between checks |
| `DOCDB_USER` | `docdbadmin` | Database username |
| `DOCDB_PASSWORD` | `Test1234` | Database password |
| `DOCDB_PORT` | `10260` | Database port |
| `DOCDB_CONTAINER` | *(empty)* | Existing container name |
| `INSPECTOR_PATH` | *(auto-detected)* | Path to inspector script |
| `ALERT_EMAIL` | *(empty)* | Email for alerts |
| `ALERT_SLACK_WEBHOOK` | *(empty)* | Slack webhook URL |
| `ALERT_PAGERDUTY_KEY` | *(empty)* | PagerDuty routing key |

---

## Prerequisites

- Docker
- Python 3.7+
- mongosh (MongoDB Shell)
- Node.js (for agent-kit build tools)

## Quick Start

```bash
# 1. Start DocumentDB
docker pull ghcr.io/documentdb/documentdb/documentdb-local:latest
docker run -dt -p 10260:10260 --name my-docdb \
  ghcr.io/documentdb/documentdb/documentdb-local:latest \
  --username docdbadmin --password Test1234

# 2. Run the ecommerce app
cd ecommerce
pip install -r requirements.txt
python app.py
# → Dashboard at http://localhost:5000
# → Health check at http://localhost:5000/api/health

# 3. Run the inspector independently
cd ../agentkit
bash skills/documentdb-inspector/documentdb-inspector.sh \
  --password Test1234 --port 10260 --container my-docdb --tls required
```

## License

MIT
