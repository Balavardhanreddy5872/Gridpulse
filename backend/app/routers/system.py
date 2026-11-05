"""
GET /api/system/info - where this running backend keeps its state.

Handy for the Milestone 4 demo: shows the database server address as seen
from Postgres itself (the Cloud SQL private IP), the storage bucket, the
Google identity in use, and the applied migration - and never any secret.
Milestone 5: also which replica (pod) and which GKE node answered, so the
demo can show requests being spread across replicas.

Milestone 6:
  GET /api/version               which release (git commit) this pod runs. The
                                 CI/CD pipeline polls it through the public URL
                                 to confirm the new release - or, after an
                                 automatic rollback, the previous one - is the
                                 one serving traffic.
  GET /api/system/simulate-error a CONTROLLED HTTP 5xx for the monitoring demo.
                                 It touches no data. Its JSON log entry is
                                 counted by the gridpulse_http_5xx log-based
                                 metric, which drives the dashboard's error
                                 chart and the "HTTP 5xx errors" alert policy.
"""
import os
import socket

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.logging_config import APP_VERSION
from app.services.storage import get_storage

router = APIRouter(tags=["system"])

def _pod_name() -> str:
    return os.environ.get("POD_NAME") or socket.gethostname()


class SimulatedFailure(RuntimeError):
    """Raised on purpose by GET /api/system/simulate-error."""


@router.get("/api/version")
def version():
    return {"service": "gridpulse-backend", "version": APP_VERSION, "pod": _pod_name()}


@router.get("/api/system/simulate-error")
def simulate_error(status: int = Query(500, ge=500, le=504, description="HTTP status to return (500-504)")):
    """Return a deliberate server error (default: an unhandled exception -> 500).

    Only for the Milestone 6 observability demo; enabled by
    ENABLE_ERROR_SIMULATION=true (k8s/backend-configmap.yaml)."""
    if not settings.ENABLE_ERROR_SIMULATION:
        raise HTTPException(status_code=404, detail="Not Found")
    if status == 500:
        # An unhandled exception: logged with its stack trace (Error Reporting),
        # turned into a JSON 500 by app/request_logging.py.
        raise SimulatedFailure("Controlled failure for the Milestone 6 demo (no data was touched)")
    return JSONResponse(
        status_code=status,
        content={"detail": f"Controlled HTTP {status} for the Milestone 6 demo", "pod": _pod_name()},
    )


@router.get("/api/system/info")
def system_info(db: Session = Depends(get_db)):
    info = {
        "version": APP_VERSION,
        "served_by": {
            "pod": _pod_name(),
            "node": os.environ.get("NODE_NAME"),
            "namespace": os.environ.get("POD_NAMESPACE"),
        },
        "database": {"configured_via": "Secret Manager + Cloud SQL" if settings.uses_cloud_database else "DATABASE_URL"},
        "storage": {"backend": settings.STORAGE_BACKEND, "location": get_storage().describe()},
    }
    try:
        row = db.execute(text(
            "SELECT host(inet_server_addr()), current_setting('server_version'), "
            "current_database(), current_user, "
            "(SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid())"
        )).one()
        info["database"].update(
            server_address=row[0], server_version=row[1], database=row[2], user=row[3], tls=row[4]
        )
        info["database"]["migration"] = db.execute(text("SELECT version_num FROM alembic_version")).scalar()
    except Exception as exc:  # noqa: BLE001 - e.g. SQLite in the test suite
        db.rollback()
        info["database"]["detail"] = f"unavailable: {exc.__class__.__name__}"
    if settings.uses_cloud_database or settings.STORAGE_BACKEND == "gcs":
        from app import gcp

        info["identity"] = gcp.whoami()
    return info
