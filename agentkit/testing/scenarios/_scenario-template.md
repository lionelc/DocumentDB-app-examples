# Scenario: [Scenario Name]

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

[Brief description of what the inspector should do in this scenario]

## Prerequisites

- Docker installed and running
- mongosh available
- DocumentDB image pulled (unless testing pull failure)

## Setup Steps

[Steps to prepare the environment for this scenario]

```bash
# Example setup commands
```

## Inspector Command

```bash
documentdb-inspector.sh --password <pass> [OPTIONS]
```

## Expected Outcome

| Check | Expected Status | Error Code |
|-------|----------------|------------|
| Docker available | PASS / FAIL | |
| Image pulled | PASS / FAIL / SKIP | |
| Container started | PASS / FAIL | |
| Port reachable | PASS / FAIL | |
| TLS handshake | PASS / FAIL / SKIP | |
| Smoke test (CRUD) | PASS / FAIL | |

## Success Criteria

- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Notes

[Additional context]
