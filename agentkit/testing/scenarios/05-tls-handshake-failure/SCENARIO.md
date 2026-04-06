# Scenario: TLS Handshake Failure

> **Important**: This file defines the fixed requirements for this test scenario.
> Do NOT modify this file between iterations — the point is to measure improvement
> with the same requirements.

## Overview

Start a plain TCP echo server on the DocumentDB port and run the inspector with
`--tls required`. The TLS handshake check should fail because the server does not speak
TLS, producing error code `TLS_HANDSHAKE_FAILED`.

## Prerequisites

- Docker installed and running
- mongosh available on PATH
- `openssl` available on PATH (used by the inspector for TLS probing)
- No other process using the test port

## Setup Steps

```bash
source testing/harness/helpers.sh
cleanup_inspector_containers
cleanup_main_container

# Start a plain TCP server on port 10260 (no TLS)
python3 -c "
import socket, time, threading
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 10260))
s.listen(1)
def handle():
    while True:
        try:
            conn, _ = s.accept()
            conn.sendall(b'not-tls\n')
            conn.close()
        except: break
t = threading.Thread(target=handle, daemon=True)
t.start()
time.sleep(300)
" &
PLAIN_PID=$!
sleep 1
```

## Inspector Command

```bash
documentdb-inspector.sh \
  --password Test1234 \
  --port 10260 \
  --tls required \
  --check-only
```

## Expected Outcome

| Check              | Expected Status | Error Code            |
|--------------------|----------------|-----------------------|
| Docker available   | *(not run)*    |                       |
| Image pulled       | *(not run)*    |                       |
| Container started  | *(not run)*    |                       |
| Port reachable     | PASS           |                       |
| TLS handshake      | FAIL           | TLS_HANDSHAKE_FAILED  |
| Smoke test (CRUD)  | *(not run)*    |                       |

## Success Criteria

- [ ] `--check-only` skips Docker, image, and container checks
- [ ] Port reachable passes (the plain TCP server is listening)
- [ ] TLS handshake fails with `TLS_HANDSHAKE_FAILED`
- [ ] Output includes `openssl s_client` failure details (e.g., "wrong version number")
- [ ] "How to fix" hint suggests `--tls off` or `--tls prefer`
- [ ] Overall status is `FAIL`
- [ ] Exit code is non-zero

## Teardown

```bash
kill $PLAIN_PID 2>/dev/null || true
```

## Notes

- `--check-only` is used so the inspector does not try to pull images or start
  containers — it goes straight to port, TLS, and CRUD checks.
- With `--tls required` the inspector runs `openssl s_client` against the port. A plain
  TCP server cannot complete the handshake, so the check fails.
- If `--tls prefer` were used instead, the check would produce `WARN` and fall back to
  plaintext — that is tested implicitly but is not the focus of this scenario.
