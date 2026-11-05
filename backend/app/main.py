import logging
from contextlib import asynccontextmanager

import anyio.to_thread
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.logging_config import APP_VERSION, setup_logging

# Milestone 6: JSON logs on stdout (Cloud Logging reads them as jsonPayload).
# Done before anything else is imported so every module's logger uses it.
setup_logging()

from app.config import settings  # noqa: E402
from app.database import engine  # noqa: E402
from app import models  # noqa: E402,F401 - registers the ORM models
from app.request_logging import install_request_logging  # noqa: E402
from app.routers import health, regions, forecast, alerts, documents, jobs, system  # noqa: E402
from app.services.storage import get_storage  # noqa: E402
from app.workers.spike_worker import start_worker  # noqa: E402

logger = logging.getLogger("gridpulse")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Milestone 4: tables are created by the Alembic migration
    # (backend/migrations/versions/0001_initial_schema.py, run by start.sh
    # as `alembic upgrade head`), no longer by create_all() here.
    # Milestone 5: cap concurrent requests per pod (see config.REQUEST_THREADS).
    anyio.to_thread.current_default_thread_limiter().total_tokens = settings.REQUEST_THREADS
    logger.info("GridPulse backend %s starting", APP_VERSION, extra={"event": "startup"})
    logger.info("Request threads per pod: %d", settings.REQUEST_THREADS)
    logger.info("Database: %s", engine.url.render_as_string(hide_password=True))
    logger.info("File storage: %s", get_storage().describe())
    if settings.uses_cloud_database or settings.STORAGE_BACKEND == "gcs":
        from app import gcp

        who = gcp.whoami()
        logger.info("Google Cloud identity: %s (via %s)", who["identity"], who["source"])

    worker_task = start_worker()
    try:
        yield
    finally:
        worker_task.cancel()


app = FastAPI(
    title="GridPulse API",
    description="Smart Grid Load Forecasting & Peak-Risk Alerting Platform",
    version=f"0.6.0-milestone6+{APP_VERSION}",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Milestone 6: every request is logged as one JSON entry (status, latency,
# route, request id). Unhandled exceptions are logged with their stack trace and
# turned into a clean JSON 500 there - see app/request_logging.py.
install_request_logging(app, project=settings.GCP_PROJECT)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Safety net for errors raised outside the request-logging middleware:
    # never let the API crash silently - always return a clean JSON error the
    # frontend can display (without echoing internal details).
    logger.error("Unhandled %s: %s", exc.__class__.__name__, exc, exc_info=exc,
                 extra={"event": "unhandled_exception"})
    return JSONResponse(
        status_code=500,
        content={"detail": f"Unexpected server error: {exc.__class__.__name__}"},
    )


app.include_router(health.router)
app.include_router(regions.router)
app.include_router(forecast.router)
app.include_router(alerts.router)
app.include_router(documents.router)
app.include_router(jobs.router)
app.include_router(system.router)


@app.get("/")
def root():
    return {
        "service": "GridPulse API",
        "version": APP_VERSION,
        "docs": "/docs",
        "health": "/api/health",
    }
