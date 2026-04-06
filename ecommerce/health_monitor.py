"""
DocumentDB Health Monitor
=========================
Periodically runs the documentdb-inspector agent-kit to diagnose database
health and sends alerts to the site owner when issues are detected.

This module integrates the inspector as an "agent-to-agent" invocation:
  1. Every CHECK_INTERVAL seconds, run documentdb-inspector.sh --json
  2. Parse the JSON report
  3. If any check fails → trigger an alert (email, Slack, PagerDuty, etc.)
  4. Expose current health status via get_status() for the /api/health endpoint

Architecture:
                                  ┌──────────────────────┐
  ┌──────────┐   hourly cron      │ documentdb-inspector  │
  │ Flask App │ ────────────────► │     .sh --json        │
  │  (app.py) │                   │  (subprocess call)    │
  │           │ ◄──────────────── │  returns JSON report  │
  │           │   parse report    └──────────────────────┘
  │           │
  │  if FAIL ─┼──► send_alert()
  │           │      │
  │           │      ├─► Email   (SMTP / SES / SendGrid)
  │           │      ├─► Slack   (Incoming Webhook)
  │           │      ├─► PagerDuty (Events API v2)
  │           │      └─► Custom  (any HTTP callback)
  └──────────┘
"""

import json
import os
import subprocess
import threading
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path


# ── Configuration ─────────────────────────────────────────────────────

# How often to run the inspector (seconds). Default: 3600 (1 hour).
CHECK_INTERVAL = int(os.environ.get("HEALTH_CHECK_INTERVAL", 3600))

# Path to the inspector script (resolve relative to this file's location)
_THIS_DIR = Path(__file__).resolve().parent
INSPECTOR_PATH = os.environ.get(
    "INSPECTOR_PATH",
    str(_THIS_DIR / "../../agentkit/skills/documentdb-inspector/documentdb-inspector.sh"),
)

# Database connection details (passed to the inspector)
DB_USER = os.environ.get("DOCDB_USER", "docdbadmin")
DB_PASSWORD = os.environ.get("DOCDB_PASSWORD", "Test1234")
DB_PORT = os.environ.get("DOCDB_PORT", "10260")
DB_CONTAINER = os.environ.get("DOCDB_CONTAINER", "")  # empty = let inspector manage
TLS_MODE = os.environ.get("DOCDB_TLS", "required")

# Alert configuration
# In production, set these via environment variables or a config file.
ALERT_EMAIL = os.environ.get("ALERT_EMAIL", "")           # e.g. "ops@company.com"
ALERT_SLACK_WEBHOOK = os.environ.get("ALERT_SLACK_WEBHOOK", "")  # e.g. "https://hooks.slack.com/..."
ALERT_PAGERDUTY_KEY = os.environ.get("ALERT_PAGERDUTY_KEY", "")  # e.g. routing key


# ── Health state ──────────────────────────────────────────────────────

_health_status = {
    "status": "unknown",          # "healthy", "unhealthy", "unknown", "error"
    "last_check": None,           # ISO timestamp of last check
    "next_check": None,           # ISO timestamp of next scheduled check
    "checks": [],                 # list of individual check results
    "findings": [],               # list of failed checks with error details
    "inspector_version": None,
    "check_count": 0,             # total checks run since startup
    "alert_count": 0,             # total alerts sent since startup
    "consecutive_failures": 0,    # for alert escalation
}
_status_lock = threading.Lock()
_timer = None
_running = False


def get_status():
    """Return current health status (thread-safe). Used by /api/health."""
    with _status_lock:
        return dict(_health_status)


# ── Inspector invocation ──────────────────────────────────────────────

def _run_inspector():
    """
    Execute documentdb-inspector.sh and return the parsed JSON report.
    This is the agent-to-agent invocation: our app calls the inspector
    as a subprocess, gets structured JSON back, and makes decisions.
    """
    cmd = [
        "bash", INSPECTOR_PATH,
        "--password", DB_PASSWORD,
        "--user", DB_USER,
        "--port", DB_PORT,
        "--tls", TLS_MODE,
        "--json",
        "--timeout", "90",
    ]

    # If a specific container is configured, inspect it directly
    if DB_CONTAINER:
        cmd.extend(["--container", DB_CONTAINER])
    else:
        cmd.extend(["--check-only"])

    report_file = f"/tmp/docdb-health-{os.getpid()}.json"
    cmd.extend(["--report", report_file])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
        )

        # Parse JSON report (prefer file, fall back to stdout)
        if os.path.exists(report_file):
            with open(report_file) as f:
                report = json.load(f)
            os.unlink(report_file)
        elif result.stdout.strip():
            report = json.loads(result.stdout)
        else:
            return {
                "overallStatus": "FAIL",
                "checks": [],
                "error": f"Inspector exited {result.returncode}: {result.stderr[:500]}",
            }

        return report

    except subprocess.TimeoutExpired:
        return {"overallStatus": "FAIL", "checks": [], "error": "Inspector timed out after 120s"}
    except Exception as e:
        return {"overallStatus": "FAIL", "checks": [], "error": str(e)}


# ── Alert dispatch ────────────────────────────────────────────────────

def send_alert(findings, report):
    """
    Send an alert when the inspector detects issues.

    In production, implement one or more of these channels:

    1. EMAIL (SMTP / Amazon SES / SendGrid):
       ```
       import smtplib
       from email.mime.text import MIMEText

       msg = MIMEText(alert_body)
       msg["Subject"] = f"[DocumentDB Alert] {len(findings)} issue(s) detected"
       msg["From"] = "docdb-monitor@company.com"
       msg["To"] = ALERT_EMAIL

       with smtplib.SMTP("smtp.company.com", 587) as server:
           server.starttls()
           server.login("user", "password")
           server.send_message(msg)
       ```

    2. SLACK (Incoming Webhook):
       ```
       import requests

       requests.post(ALERT_SLACK_WEBHOOK, json={
           "text": f":warning: *DocumentDB Health Alert*",
           "blocks": [{
               "type": "section",
               "text": {"type": "mrkdwn", "text": alert_body}
           }]
       })
       ```

    3. PAGERDUTY (Events API v2):
       ```
       import requests

       requests.post("https://events.pagerduty.com/v2/enqueue", json={
           "routing_key": ALERT_PAGERDUTY_KEY,
           "event_action": "trigger",
           "payload": {
               "summary": f"DocumentDB: {findings[0]['errorCode']}",
               "severity": "critical",
               "source": "documentdb-inspector",
               "custom_details": report
           }
       })
       ```

    4. CUSTOM WEBHOOK (any HTTP endpoint):
       ```
       import requests

       requests.post("https://api.company.com/alerts", json={
           "service": "documentdb",
           "status": "unhealthy",
           "findings": findings,
           "timestamp": datetime.now(timezone.utc).isoformat()
       })
       ```
    """
    # ── Placeholder implementation: log to console ──
    now = datetime.now(timezone.utc).isoformat()
    print(f"\n{'='*70}")
    print(f"  ⚠️  DOCUMENTDB HEALTH ALERT  —  {now}")
    print(f"{'='*70}")
    for f in findings:
        print(f"  FINDING: {f.get('name', '?')}  ({f.get('errorCode', '?')})")
        print(f"    {f.get('error', 'no details')[:200]}")
    print(f"{'='*70}")
    print(f"  To configure real alerts, set environment variables:")
    print(f"    ALERT_EMAIL          — email address for SMTP alerts")
    print(f"    ALERT_SLACK_WEBHOOK  — Slack incoming webhook URL")
    print(f"    ALERT_PAGERDUTY_KEY  — PagerDuty routing key")
    print(f"{'='*70}\n")


def send_recovery_alert(previous_failures):
    """
    Send a recovery notification when health returns to normal after failures.

    In production, this would clear PagerDuty incidents or send a green Slack
    message. Same channels as send_alert() above.
    """
    now = datetime.now(timezone.utc).isoformat()
    print(f"\n  ✅  DOCUMENTDB RECOVERED  —  {now}")
    print(f"      System healthy after {previous_failures} consecutive failure(s).\n")


# ── Periodic check loop ──────────────────────────────────────────────

def _check_and_schedule():
    """Run one health check, update state, alert if needed, then reschedule."""
    global _timer, _running

    if not _running:
        return

    now = datetime.now(timezone.utc)
    print(f"[HealthMonitor] Running inspector check at {now.isoformat()} ...")

    report = _run_inspector()

    # Extract findings (failed checks)
    findings = [
        c for c in report.get("checks", [])
        if c.get("status") == "FAIL"
    ]

    with _status_lock:
        previous_failures = _health_status["consecutive_failures"]

        _health_status["last_check"] = now.isoformat()
        _health_status["check_count"] += 1
        _health_status["checks"] = report.get("checks", [])
        _health_status["findings"] = findings

        if report.get("overallStatus") == "PASS":
            _health_status["status"] = "healthy"
            _health_status["consecutive_failures"] = 0

            # Send recovery alert if we were previously failing
            if previous_failures > 0:
                send_recovery_alert(previous_failures)
        else:
            _health_status["status"] = "unhealthy"
            _health_status["consecutive_failures"] += 1
            _health_status["alert_count"] += 1

            send_alert(findings, report)

        # Schedule next check
        _health_status["next_check"] = (
            datetime.now(timezone.utc) + timedelta(seconds=CHECK_INTERVAL)
        ).isoformat()

    total_checks = report.get("checks", [])
    passed = sum(1 for c in total_checks if c.get("status") in ("PASS", "SKIP"))
    status_str = "✅ healthy" if not findings else f"⚠️  {len(findings)} issue(s)"
    print(f"[HealthMonitor] Result: {status_str}  ({passed}/{len(total_checks)} checks passed)")
    print(f"[HealthMonitor] Next check in {CHECK_INTERVAL}s")

    # Reschedule
    if _running:
        _timer = threading.Timer(CHECK_INTERVAL, _check_and_schedule)
        _timer.daemon = True
        _timer.start()


# ── Public API ────────────────────────────────────────────────────────

def start(run_immediately=True):
    """
    Start the health monitor background thread.
    Call this from app.py's initialize_server().

    Args:
        run_immediately: If True, run first check right away.
                        If False, wait CHECK_INTERVAL before first check.
    """
    global _running, _timer

    if _running:
        return

    _running = True
    print(f"[HealthMonitor] Starting (interval={CHECK_INTERVAL}s, "
          f"inspector={INSPECTOR_PATH})")

    if run_immediately:
        # Run first check in a background thread (don't block startup)
        _timer = threading.Timer(2, _check_and_schedule)
    else:
        _timer = threading.Timer(CHECK_INTERVAL, _check_and_schedule)

    _timer.daemon = True
    _timer.start()


def stop():
    """Stop the health monitor. Call this from shutdown_handler()."""
    global _running, _timer

    _running = False
    if _timer:
        _timer.cancel()
        _timer = None

    print("[HealthMonitor] Stopped")
