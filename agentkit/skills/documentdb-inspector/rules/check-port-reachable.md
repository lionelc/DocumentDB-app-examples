---
title: Port Reachability
impact: HIGH
impactDescription: unreachable port prevents all client connections
tags: [check, network, port, tcp]
---

## Port Reachability

The inspector tests that the DocumentDB container port is reachable via TCP. This check succeeds if a TCP connection can be established within 10 seconds.

**Symptom (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass --port 10260 --check-only
ERROR: Port reachable  (PORT_UNREACHABLE)
  Cannot reach localhost:10260
```

**Resolution (Correct state):**

```bash
# Verify the container is running
docker ps --filter "name=my-docdb"

# Check from the host
timeout 5 bash -c 'echo > /dev/tcp/localhost/10260' && echo "reachable" || echo "unreachable"

# If using Docker Desktop, ensure port forwarding is active
# If using a remote host, check firewall rules
```

The check uses bash's built-in `/dev/tcp` pseudo-device for a lightweight TCP probe without requiring additional tools.

**Error code:** `PORT_UNREACHABLE`
