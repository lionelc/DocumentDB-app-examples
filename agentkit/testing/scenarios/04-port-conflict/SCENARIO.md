# Scenario: Port Conflict

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Occupy the default DocumentDB port (10260) with a dummy listener before running the
inspector. The inspector should detect the port conflict when attempting to start a new
container and report `PORT_IN_USE`.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- No other process using port 10260 (we will occupy it ourselves)

## Setup Steps

```bash
# Remove any existing inspector containers so the inspector tries to create a new one
source testing/harness/helpers.sh
cleanup_inspector_containers
cleanup_main_container

# Start a dummy listener on the target port
python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 10260))
s.listen(1)
time.sleep(300)
" &
DUMMY_PID=$!

# Verify the port is occupied
sleep 1
ss -tlnp | grep 10260
```

## Inspector Command

```bash
documentdb-inspector.sh --password Test1234 --port 10260
```

## Expected Outcome

| Check              | Expected Status | Error Code   |
|--------------------|----------------|--------------|
| Docker available   | PASS           |              |
| Image pulled       | PASS           |              |
| Container started  | FAIL           | PORT_IN_USE  |
| Port reachable     | *(not run)*    |              |
| TLS handshake      | *(not run)*    |              |
| Smoke test (CRUD)  | *(not run)*    |              |

## Success Criteria

- [ ] Docker available and Image pulled both pass
- [ ] Container started fails with error code `PORT_IN_USE`
- [ ] Output mentions port 10260 is already in use
- [ ] "How to fix" hint suggests `ss -tlnp | grep 10260` or `--port <other>`
- [ ] Overall status is `FAIL`
- [ ] Exit code is non-zero

## Teardown

```bash
# Kill the dummy listener
kill $DUMMY_PID 2>/dev/null || true
```

## Notes

- The inspector checks port availability with `ss -tlnp` before calling `docker run`.
  If the port is occupied, it fails fast without attempting container creation.
- An alternative trigger is if `docker run` itself returns a "port already allocated"
  error — the inspector also maps that to `PORT_IN_USE`.
