"""
GET /api/system/info - where this running backend keeps its state.

Handy for the Milestone 4 demo: shows the database server address as seen
from Postgres itself (the Cloud SQL private IP), the storage bucket, the
Google identity in use, and the applied migration - and never any secret.
Milestone 5: also which replica (pod) and which GKE node answered, so the
demo can show requests being spread across replicas.
"""
import os
import socket

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.services.storage import get_storage

router = APIRouter(tags=["system"])


@router.get("/api/system/info")
def system_info(db: Session = Depends(get_db)):
    info = {
        "served_by": {
            "pod": os.environ.get("POD_NAME") or socket.gethostname(),
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
