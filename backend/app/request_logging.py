"""
Milestone 6: one structured log entry per HTTP request.

    {"severity": "ERROR", "message": "GET /api/system/simulate-error -> 500 (3 ms)",
     "event": "http_request", "method": "GET", "path": "/api/system/simulate-error",
     "route": "/api/system/simulate-error", "status_code": 500, "status_class": "5xx",
     "duration_ms": 3.1, "request_id": "4f0c...", "probe": false,
     "httpRequest": {"requestMethod": "GET", "requestUrl": "/api/...", "status": 500,
                     "latency": "0.003s", "userAgent": "curl/8.7.1", "remoteIp": "..."}, ...}

* severity follows the status: 5xx -> ERROR, 4xx -> WARNING, else INFO.
* The log-based metric gridpulse_http_5xx (terraform/monitoring.tf) counts
  entries with event="http_request", probe=false and status_code >= 500.
* Health checks (kubelet probes, the load balancer's GoogleHC, Cloud Monitoring
  uptime checks) are tagged probe=true. Successful ones are not logged at all
  (there are dozens per minute); failed ones are, so a pod that keeps failing
  its readiness probe is still visible in the logs.
* An unhandled exception is turned into a JSON 500 HERE, after logging it
  once with its stack trace (Cloud Error Reporting picks that entry up), so
  the client always gets {"detail": ..., "request_id": ...} and the error is
  never logged twice.
"""
from __future__ import annotations

import logging
import re
import time
import uuid

import anyio
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.logging_config import request_context, trace_fields

logger = logging.getLogger("gridpulse.http")

PROBE_USER_AGENTS = (
    "kube-probe/",                       # kubelet liveness / readiness / startup probes
    "GoogleHC/",                         # Google load balancer health checks
    "GoogleStackdriverMonitoring-UptimeChecks",  # Cloud Monitoring uptime check
)


_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _request_id(request: Request) -> str:
    # Re-use the caller's X-Request-ID if it looks sane, otherwise make one.
    given = request.headers.get("x-request-id", "")
    return given if _SAFE_REQUEST_ID.match(given) else uuid.uuid4().hex[:16]


def _is_probe(user_agent: str) -> bool:
    return any(marker in user_agent for marker in PROBE_USER_AGENTS)


def _client_ip(request: Request) -> str | None:
    # The Google load balancer sends "X-Forwarded-For: <client>, <load balancer>".
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else None


def install_request_logging(app: FastAPI, project: str | None) -> None:
    @app.middleware("http")
    async def log_request(request: Request, call_next):
        started = time.perf_counter()
        request_id = _request_id(request)
        user_agent = request.headers.get("user-agent", "")
        probe = _is_probe(user_agent)

        context = {"request_id": request_id}
        context.update(trace_fields(request.headers.get("x-cloud-trace-context"), project))
        token = request_context.set(context)
        try:
            try:
                response = await call_next(request)
            except Exception as exc:  # noqa: BLE001 - the one place unhandled errors end up
                # Starlette re-raises the endpoint's error while handling its own
                # internal EndOfStream; hide that so the logged trace is just ours.
                if isinstance(exc.__context__, anyio.EndOfStream):
                    exc.__suppress_context__ = True
                logger.error(
                    "Unhandled %s on %s %s: %s",
                    exc.__class__.__name__, request.method, request.url.path, exc,
                    exc_info=exc,
                    extra={
                        "event": "unhandled_exception",
                        "error_type": exc.__class__.__name__,
                        "request_id": request_id,
                    },
                )
                response = JSONResponse(
                    status_code=500,
                    content={
                        "detail": f"Unexpected server error: {exc.__class__.__name__}",
                        "request_id": request_id,
                    },
                )

            duration = time.perf_counter() - started
            status = response.status_code
            response.headers["X-Request-ID"] = request_id

            if probe and status < 400:
                return response

            route = getattr(request.scope.get("route"), "path", None) or "unmatched"
            url = request.url.path + (f"?{request.url.query}" if request.url.query else "")
            level = logging.ERROR if status >= 500 else logging.WARNING if status >= 400 else logging.INFO
            logger.log(
                level,
                "%s %s -> %d (%.0f ms)", request.method, request.url.path, status, duration * 1000,
                extra={
                    "event": "http_request",
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "route": route,
                    "status_code": status,
                    "status_class": f"{status // 100}xx",
                    "duration_ms": round(duration * 1000, 1),
                    "probe": probe,
                    "httpRequest": {
                        key: value
                        for key, value in {
                            "requestMethod": request.method,
                            "requestUrl": url,
                            "status": status,
                            "latency": f"{duration:.3f}s",
                            "userAgent": user_agent,
                            "remoteIp": _client_ip(request),
                            "protocol": f"HTTP/{request.scope.get('http_version', '1.1')}",
                        }.items()
                        if value
                    },
                },
            )
            return response
        finally:
            request_context.reset(token)
