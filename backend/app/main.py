from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.database import Base, engine
from app import models  # noqa: F401 - ensures models are registered before create_all
from app.routers import health, regions, forecast, alerts, documents, jobs
from app.workers.spike_worker import start_worker


@asynccontextmanager
async def lifespan(app: FastAPI):
    # For a student local milestone, create_all is simpler and more reliable
    # than a full migration tool. database/init.sql documents the same
    # schema in raw SQL for anyone who wants to inspect/run it directly.
    Base.metadata.create_all(bind=engine)

    worker_task = start_worker()
    try:
        yield
    finally:
        worker_task.cancel()


app = FastAPI(
    title="GridPulse API",
    description="Smart Grid Load Forecasting & Peak-Risk Alerting Platform",
    version="0.3.0-stage3",
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


@app.get("/")
def root():
    return {
        "service": "GridPulse API",
        "docs": "/docs",
        "health": "/api/health",
    }
