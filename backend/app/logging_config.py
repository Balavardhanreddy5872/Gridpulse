"""
Milestone 6: structured (JSON) logging.

Every line the backend writes is ONE JSON object on stdout. On GKE the
logging agent turns each line into a Cloud Logging entry and reads a few
special keys:

    severity                               -> the entry's severity (INFO / WARNING / ERROR ...)
    message                                -> the summary line shown in Logs Explorer
    time                                   -> the entry's timestamp
    httpRequest                            -> the entry's HTTP request record (method, URL,
                                              status, latency) - shown like a load-balancer log
    logging.googleapis.com/trace           -> groups every line of one request together
    logging.googleapis.com/sourceLocation  -> file / line / function that logged it

Everything else stays in jsonPayload, so a Logs Explorer query or a
log-based metric can filter on it, e.g.

    jsonPayload.event="http_request" AND jsonPayload.status_code>=500

which is exactly what the gridpulse_http_5xx log-based metric counts
(terraform/monitoring.tf).

The module has no dependency on app.config, so uvicorn, Alembic
(migrations/env.py) and the tests can all use it before anything else is
imported.
"""
from __future__ import annotations

import contextvars
import datetime as _dt
import json
import logging
import os
import socket
import sys

SERVICE = "gridpulse-backend"

# Baked into the image at build time (--build-arg APP_VERSION=<git sha>, see
# backend/Dockerfile and .github/workflows/deploy.yml). The pipeline compares it
# with the commit it just deployed to know which release is serving traffic.
APP_VERSION = os.environ.get("APP_VERSION", "dev")
POD_NAME = os.environ.get("POD_NAME") or socket.gethostname()

# Set per request by the request-logging middleware (app/main.py) and added to
# every line logged while that request is being handled - including lines from
# worker threads, because Starlette copies the context into its thread pool.
request_context: contextvars.ContextVar[dict | None] = contextvars.ContextVar(
    "gridpulse_request_context", default=None
)

# Attributes every LogRecord has; anything else came from logger.x(..., extra={...}).
_STANDARD_ATTRS = set(vars(logging.LogRecord("", 0, "", 0, "", None, None))) | {
    "message",
    "asctime",
    "taskName",
    "color_message",  # uvicorn's ANSI-coloured duplicate of the message
}


def _utc_timestamp(created: float) -> str:
    ts = _dt.datetime.fromtimestamp(created, tz=_dt.timezone.utc)
    return ts.isoformat(timespec="milliseconds").replace("+00:00", "Z")


class JsonFormatter(logging.Formatter):
    """Render a LogRecord as one line of JSON in Cloud Logging's format."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict = {
            "severity": record.levelname,  # DEBUG / INFO / WARNING / ERROR / CRITICAL
            "message": record.getMessage(),
            "time": _utc_timestamp(record.created),
            "logger": record.name,
            "service": SERVICE,
            "version": APP_VERSION,
            "pod": POD_NAME,
            "logging.googleapis.com/sourceLocation": {
                "file": record.pathname,
                "line": str(record.lineno),
                "function": record.funcName,
            },
        }

        context = request_context.get()
        if context:
            entry.update(context)

        # Fields passed with extra={...}
        for key, value in record.__dict__.items():
            if key not in _STANDARD_ATTRS and not key.startswith("_"):
                entry[key] = value

        if record.exc_info:
            # Cloud Error Reporting groups ERROR entries that carry a stack trace.
            entry["stack_trace"] = self.formatException(record.exc_info)
            entry["serviceContext"] = {"service": SERVICE, "version": APP_VERSION}

        return json.dumps(entry, default=str, ensure_ascii=False)


_HANDLER_NAME = "gridpulse-json-stdout"


def setup_logging(level: str | None = None) -> None:
    """Send every log line (ours, uvicorn's, Alembic's, SQLAlchemy's) to
    stdout as JSON. Safe to call more than once."""
    level = (level or os.environ.get("LOG_LEVEL") or "INFO").upper()

    handler = logging.StreamHandler(sys.stdout)
    handler.set_name(_HANDLER_NAME)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers = [h for h in root.handlers if h.get_name() != _HANDLER_NAME]
    root.addHandler(handler)
    root.setLevel(level)

    # uvicorn installs its own plain-text handlers before importing the app;
    # route its loggers through the root JSON handler instead.
    for name in ("uvicorn", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True
    # uvicorn's own access log is replaced by our request log (app/main.py),
    # which has status codes, latency, route and request id as fields.
    access = logging.getLogger("uvicorn.access")
    access.handlers = []
    access.propagate = False
    access.disabled = True


def trace_fields(cloud_trace_header: str | None, project: str | None) -> dict:
    """Turn the Google load balancer's X-Cloud-Trace-Context header
    ("TRACE_ID/SPAN_ID;o=1") into Cloud Logging's trace fields, so Logs
    Explorer can show every line of one request together."""
    if not cloud_trace_header or not project:
        return {}
    trace_id = cloud_trace_header.split("/", 1)[0].strip()
    if not trace_id:
        return {}
    return {"logging.googleapis.com/trace": f"projects/{project}/traces/{trace_id}"}
