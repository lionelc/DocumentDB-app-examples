---
title: TLS Handshake Validation
impact: HIGH
impactDescription: TLS misconfiguration blocks all secure client connections
tags: [check, tls, ssl, security, connection]
---

## TLS Handshake Validation

The inspector validates TLS negotiation using `openssl s_client`. DocumentDB local enables TLS by default with self-signed certificates. This check is skipped when `--tls off` is used.

**Symptom (Incorrect state):**

```
$ documentdb-inspector.sh --password mypass --tls required --check-only --port 10271
ERROR: TLS handshake  (TLS_HANDSHAKE_FAILED)
  TLS handshake failed. error:0A00010B:SSL routines:ssl3_get_record:wrong version number

  How to fix:
    1. Re-run with --tls off or --tls prefer
    2. Ensure the container was started with TLS support
    3. For dev use, --tls off is acceptable
```

**Resolution (Correct state):**

```bash
# DocumentDB local has TLS enabled by default
# Connect with TLS (allow self-signed certs):
mongosh "mongodb://docdbadmin:mypass@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true"

# If TLS is not needed for development:
documentdb-inspector.sh --password mypass --tls off

# The "wrong version number" error means the server is NOT speaking TLS
# This happens when connecting to a non-TLS service with --tls required
```

The check runs `echo | openssl s_client -connect localhost:PORT` and looks for `BEGIN CERTIFICATE` in the output. With `--tls prefer`, a failed handshake falls back to plain text instead of failing.

**Error code:** `TLS_HANDSHAKE_FAILED`

**Reference:** [DocumentDB TLS configuration](https://github.com/documentdb/documentdb)
