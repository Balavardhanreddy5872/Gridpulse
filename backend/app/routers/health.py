"""
Health endpoints. Milestone 5 splits "is it alive?" from "can it serve?".

  GET /api/health/live   LIVENESS - Kubernetes RESTARTS the container when this fails.
                         Answers from the event loop only: no database, no
                         Google API, no disk. It fails only if the process is
                         wedged (event loop blocked / deadlocked), which a
                         restart actually fixes.

  GET /api/health/ready  READINESS - Kubernetes and the load balancer STOP SENDING
                         TRAFFIC to the pod while this fails (no restart).
                         Also runs SELECT 1 on Cloud SQL over the private IP,
                         through a dedicated one-connection pool, with a
                         hard time limit. Returns 503 if the database is
                         unreachable or slow.

Why they must differ: if liveness also checked the database, a Cloud SQL
maintenance blip would make every replica fail liveness at the same moment and
Kubernetes would restart them all - a restart storm that turns a few seconds of
database trouble into minutes of downtime (each restart re-reads Secret Manager,
re-runs the migration check and starts Python cold). With the split, the pods
stay up, drop out of the load balancer, and rejoin by themselves as soon as
SELECT 1 works again.

  GET /api/health        Kept unchanged for the Milestone 2-4 scripts.
"""
import asyncio
import os
import socket

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app import database
from app.config import settings
from app.database import get_db

router = APIRouter(tags=["health"])

POD_NAME = os.environ.get("POD_NAME") or socket.gethostname()


@router.get("/api/health/live")
async def liveness():
    # async + no I/O: if this cannot answer, the event loop itself is stuck.
    return {"status": "alive", "pod": POD_NAME}


@router.get("/api/health/ready")
async def readiness():
    try:
        await asyncio.wait_for(
            asyncio.to_thread(database.check_database),
            timeout=settings.READINESS_DB_TIMEOUT_SECONDS,
        )
    except asyncio.TimeoutError:
        return JSONResponse(
            status_code=503,
            content={
                "status": "not ready",
                "database": f"timeout after {settings.READINESS_DB_TIMEOUT_SECONDS:g}s",
                "pod": POD_NAME,
            },
        )
    except Exception as exc:  # noqa: BLE001 - any DB error means "don't send me traffic"
        return JSONResponse(
            status_code=503,
            content={
                "status": "not ready",
                "database": f"error: {exc.__class__.__name__}",
                "pod": POD_NAME,
            },
        )
    return {"status": "ready", "database": "ok", "pod": POD_NAME}


@router.get("/api/health")
def health_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        db_status = "ok"
    except Exception as exc:  # pragma: no cover - defensive
        db_status = f"error: {exc}"
    return {"status": "ok", "database": db_status}
