import logging
from contextlib import asynccontextmanager

import anyio.to_thread
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.database import engine
from app import models  # noqa: F401 - registers the ORM models
from app.routers import health, regions, forecast, alerts, documents, jobs, system
from app.services.storage import get_storage
from app.workers.spike_worker import start_worker

logging.basicConfig(level=logging.INFO, format="%(levelname)s:     %(name)s - %(message)s")
logger = logging.getLogger("gridpulse")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Milestone 4: tables are created by the Alembic migration
    # (backend/migrations/versions/0001_initial_schema.py, run by start.sh
    # as `alembic upgrade head`), no longer by create_all() here.
    # Milestone 5: cap concurrent requests per pod (see config.REQUEST_THREADS).
    anyio.to_thread.current_default_thread_limiter().total_tokens = settings.REQUEST_THREADS
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
    version="0.5.0-milestone5",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Never let the API crash silently on an unexpected error - always
    # return a clean JSON error the frontend can display.
    return JSONResponse(
        status_code=500,
        content={"detail": f"Unexpected server error: {exc}"},
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
        "docs": "/docs",
        "health": "/api/health",
    }
