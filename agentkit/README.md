# documentdb-agent-kit

A collection of skills for AI coding agents working with [DocumentDB](https://github.com/documentdb/documentdb) — an open-source, MongoDB-compatible document database built on PostgreSQL.

Skills follow the [Agent Skills](https://agentskills.io/) format.

## Available Skills

### documentdb-inspector

Health-check and diagnostic tool for DocumentDB local Docker containers. Runs 6 automated checks covering Docker availability, image management, container lifecycle, network reachability, TLS configuration, and CRUD operations.

**Use when:**
- Setting up DocumentDB local for the first time
- Verifying a DocumentDB container is healthy
- Diagnosing connection, TLS, or authentication failures
- Running pre-flight checks before compatibility tests
- Loading sample data for development

**Checks covered:**
- Docker Daemon Availability (Critical)
- Image Pull Verification (Critical)
- Container Startup (Critical)
- Port Reachability (High)
- TLS Handshake (High)
- CRUD Smoke Test (High)

## Installation

```bash
# Clone and install
git clone https://github.com/documentdb/documentdb-agent-kit.git
cd documentdb-agent-kit
npm install
npm run build
```

## Usage

Skills are automatically available once installed. The agent will use them when relevant tasks are detected.

**Examples:**
```
Help me set up DocumentDB local from scratch
```
```
Check that my DocumentDB container is healthy
```
```
My app can't connect to DocumentDB — diagnose the issue
```

## Running the Inspector Directly

```bash
./skills/documentdb-inspector/documentdb-inspector.sh \
  --password <your-password> \
  --port 10260 \
  --tls required
```

## Running Tests

```bash
npm test
# or
bash testing/harness/run-all-scenarios.sh
```

## Skill Structure

Each skill contains:
- `SKILL.md` — Instructions for the agent (triggers activation)
- `AGENTS.md` — Compiled rules (what agents read)
- `rules/` — Individual rule files
- `metadata.json` — Version and metadata

## Compatibility

Works with Claude Code, GitHub Copilot, Gemini CLI, and other Agent Skills-compatible tools.

## Prerequisites

- Docker
- mongosh (MongoDB Shell)
- Python 3.7+
- openssl (for TLS checks)

## License

MIT
