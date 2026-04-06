# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, Copilot, etc.) when working with code in this repository.

## Repository Overview

A collection of skills for AI coding agents working with [DocumentDB](https://github.com/documentdb/documentdb) — an open-source, MongoDB-compatible document database built on PostgreSQL. Skills are packaged instructions, diagnostic tools, and rules that extend agent capabilities.

## Quick Start — What Users Can Ask

When a user asks any of the following, run the corresponding scenario script. All scripts are self-contained and can be run directly from the repository root.

### Setup & Health

| User prompt | Command to run |
|-------------|---------------|
| "Help me set up DocumentDB locally" | `bash testing/scenarios/00-start-from-scratch/run.sh` |
| "Load some sample data so I can play around" | `bash testing/scenarios/01-load-sample-data/run.sh` |
| "Is my DocumentDB healthy?" | `bash testing/scenarios/02-happy-path/run.sh` |

### Diagnostics

| User prompt | Command to run |
|-------------|---------------|
| "Docker doesn't seem to be working" | `bash testing/scenarios/03-docker-not-running/run.sh` |
| "Something is using my port" | `bash testing/scenarios/04-port-conflict/run.sh` |
| "TLS isn't working" / "Can't connect with TLS" | `bash testing/scenarios/05-tls-handshake-failure/run.sh` |
| "Authentication failed" / "Wrong password" | `bash testing/scenarios/06-auth-failure/run.sh` |
| "Can't pull the image" / "Network issue" | `bash testing/scenarios/07-image-pull-failure/run.sh` |
| "Keep the container running after inspection" | `bash testing/scenarios/08-keep-container/run.sh` |
| "Test with a specific version" | `bash testing/scenarios/09-custom-image-tag/run.sh` |
| "Run a pre-flight check before my tests" | `bash testing/scenarios/10-programmatic-invocation/run.sh` |

### Benchmarking & Compatibility

| User prompt | Command to run |
|-------------|---------------|
| "How fast is DocumentDB compared to MongoDB?" | `bash testing/scenarios/01-load-sample-data/compare_run.sh` |
| "Do queries produce the same results as MongoDB?" | `bash testing/scenarios/01-load-sample-data/compare_run.sh` |
| "Benchmark DocumentDB performance" | `bash testing/scenarios/01-load-sample-data/compare_run.sh` |
| "Run the compatibility tests" | `bash testing/scenarios/11-compatibility-tests/run.sh` |
| "Does DocumentDB pass the functional tests?" | `bash testing/scenarios/11-compatibility-tests/run.sh` |

### Running Multiple Scenarios

```bash
# Run all scenarios
bash testing/harness/run-all-scenarios.sh

# Run specific scenarios by number
bash testing/harness/run-all-scenarios.sh 4        # port conflict only
bash testing/harness/run-all-scenarios.sh 3 5 6    # docker, TLS, auth
```

## Creating a New Skill

### Directory Structure

```
skills/
  {skill-name}/           # kebab-case directory name
    SKILL.md              # Required: skill definition
    AGENTS.md             # Required: compiled rules (generated)
    metadata.json         # Required: version and metadata
    README.md             # Required: documentation
    rules/                # Required for rule-based skills
      {prefix}-{name}.md  # Individual rule files
    *.sh                  # Optional: executable tools
```

### Naming Conventions

- **Skill directory**: `kebab-case` (e.g., `documentdb-inspector`)
- **SKILL.md**: Always uppercase, always this exact filename
- **AGENTS.md**: Always uppercase, always this exact filename
- **Rule files**: `prefix-description.md` (e.g., `check-docker-available.md`)

### Rule File Format

Each rule uses YAML frontmatter followed by markdown content:

```markdown
---
title: Rule Title
impact: CRITICAL | HIGH | MEDIUM | LOW
impactDescription: brief impact summary
tags: [tag1, tag2]
---

## Rule Title

Description of the rule.

**Symptom (Incorrect state):**
\`\`\`
example of the problem
\`\`\`

**Resolution (Correct state):**
\`\`\`bash
example of the fix
\`\`\`
```

### Best Practices for Context Efficiency

Skills are loaded on-demand — only the skill name and description are loaded at startup. The full `SKILL.md` loads into context only when the agent decides the skill is relevant. To minimize context usage:

- **Keep SKILL.md under 500 lines** — put detailed reference material in AGENTS.md
- **Write specific descriptions** — helps the agent know exactly when to activate the skill
- **Use progressive disclosure** — reference supporting files that get read only when needed

## Output

The build process compiles individual rule files into `AGENTS.md`:

```bash
npm run build
# or
node scripts/compile.js
```

## End-User Installation

**Claude Code:**
```bash
cp -r skills/documentdb-inspector ~/.claude/skills/
```

**GitHub Copilot / VS Code:**
```bash
cp -r skills/documentdb-inspector ~/.copilot/skills/
```
