# DocumentDB Inspector — Testing

This directory contains the test harness and scenarios for the DocumentDB Inspector skill.

## Structure

```
testing/
├── README.md                   # This file
├── harness/
│   ├── run-all-scenarios.sh    # Automated scenario runner
│   └── helpers.sh              # Common setup/teardown functions
└── scenarios/
    ├── _scenario-template.md   # Template for new scenarios
    ├── 00-start-from-scratch/  # Setup from scratch
    ├── 01-load-sample-data/    # Load sample datasets
    ├── 02-happy-path/          # All checks pass
    ├── 03-docker-not-running/  # Docker daemon unavailable
    ├── 04-port-conflict/       # Port already in use
    ├── 05-tls-handshake-failure/ # TLS negotiation fails
    ├── 06-auth-failure/        # Wrong credentials
    ├── 07-image-pull-failure/  # Image not available
    ├── 08-keep-container/      # --keep flag behaviour
    ├── 09-custom-image-tag/    # Specific image version
    └── 10-programmatic-invocation/ # JSON output parsing
```

## Running All Scenarios

```bash
# From repository root
npm test

# Or directly
bash testing/harness/run-all-scenarios.sh
```

The runner exercises each scenario, captures all output to a timestamped log file at the repository root: `agent-kit-inspector-scenarios-runlog-YYYYMMDDHHMMSS.log`

## Expected Results

| Scenario | Expected Error Code | Description |
|----------|-------------------|-------------|
| 00 | *(none — all pass)* | Fresh setup from scratch |
| 01 | *(none)* | Sample data loads successfully |
| 02 | *(none — all pass)* | Happy path health check |
| 03 | `DOCKER_NOT_FOUND` | Simulated Docker unavailability |
| 04 | `PORT_IN_USE` | Port pre-occupied by listener |
| 05 | `TLS_HANDSHAKE_FAILED` | Plain TCP server, TLS required |
| 06 | `AUTH_FAILED` | Wrong password provided |
| 07 | `IMAGE_PULL_FAILED` | Non-existent image tag |
| 08 | *(none — all pass)* | Container survives after inspect |
| 09 | *(none — all pass)* | Specific image tag verified |
| 10 | *(none — all pass)* | JSON parsed programmatically |

## Creating a New Scenario

1. Copy `scenarios/_scenario-template.md` to a new directory
2. Fill in the scenario details
3. Add the scenario function to `harness/run-all-scenarios.sh`
