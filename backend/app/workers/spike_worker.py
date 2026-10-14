"""
Stage 3 async worker.

This is the piece that turns "POST /api/jobs/simulate-spike" from just a
row-insert into an actual asynchronous workload: a background asyncio
task, started at FastAPI startup, that continuously polls async_jobs for
queued rows and processes several at once via asyncio.to_thread (so
each job's blocking DB + ML-inference work runs off the event loop and
the API stays responsive to normal requests while a spike is draining).

Local-dev design, matching the "don't require AWS for the local
milestone" guidance: a single in-process asyncio loop instead of
Celery/RQ/Redis. The job contract (status: queued -> processing ->
completed/failed, stored in Postgres) is exactly what would sit behind
Amazon SQS + a Lambda/ECS worker in the cloud version - swapping the
poll loop for an SQS consumer later doesn't change the schema, the API,
or the frontend.
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from app.config import settings
from app.database import SessionLocal
from app.models import AsyncJob, Region
from app.services.forecast_service import run_forecast

logger = logging.getLogger("gridpulse.worker")

POLL_INTERVAL_SECONDS = 1.5
MAX_CONCURRENT_JOBS = 3
STALE_CHECK_SECONDS = 60


async def _process_job(job_id: int):
    """Runs one job's DB work in a thread so the event loop isn't blocked."""
    def _work():
        db = SessionLocal()
        try:
            job = db.get(AsyncJob, job_id)
            if not job or job.status != "queued":
                return  # picked up by another poll cycle already, or gone
            job.status = "processing"
            job.started_at = datetime.now(timezone.utc)
            db.commit()

            region = db.get(Region, job.region_id) if job.region_id else None
            if region is None:
                raise ValueError(f"Region {job.region_id} not found for job {job_id}")

            run_forecast(db, region)

            job = db.get(AsyncJob, job_id)
            job.status = "completed"
            job.completed_at = datetime.now(timezone.utc)
            db.commit()
        except Exception as exc:  # noqa: BLE001 - a failed job must not crash the worker
            db.rollback()
            job = db.get(AsyncJob, job_id)
            if job:
                job.status = "failed"
                job.completed_at = datetime.now(timezone.utc)
                job.error_message = str(exc)[:500]
                db.commit()
            logger.warning("Job %s failed: %s", job_id, exc)
        finally:
            db.close()

    await asyncio.to_thread(_work)


def requeue_stale_jobs() -> int:
    """Milestone 4: the job queue lives in Cloud SQL, so it outlives the VM.
    If the VM (or container) died while a job was "processing", that job
    would otherwise stay stuck forever. At start-up and then every minute,
    put any job that has been processing for longer than STALE_JOB_MINUTES
    back in the queue (a real forecast job takes seconds)."""
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=settings.STALE_JOB_MINUTES)
    db = SessionLocal()
    try:
        stale = (
            db.query(AsyncJob)
            .filter(AsyncJob.status == "processing", AsyncJob.started_at < cutoff)
            .all()
        )
        for job in stale:
            job.status = "queued"
            job.started_at = None
        db.commit()
        if stale:
            logger.warning("Re-queued %d job(s) left in 'processing' by a previous run", len(stale))
        return len(stale)
    finally:
        db.close()


async def _requeue_stale_jobs_safely():
    try:
        await asyncio.to_thread(requeue_stale_jobs)
    except Exception:  # noqa: BLE001 - never stop the worker over this
        logger.exception("Could not re-queue stale jobs")


async def _poll_loop():
    # Checked at start-up AND every minute: a replacement VM may come up
    # before an orphaned job has been "processing" for STALE_JOB_MINUTES.
    await _requeue_stale_jobs_safely()
    last_stale_check = asyncio.get_running_loop().time()
    logger.info("GridPulse spike worker started (poll every %ss, up to %s concurrent jobs)",
                POLL_INTERVAL_SECONDS, MAX_CONCURRENT_JOBS)
    while True:
        try:
            db = SessionLocal()
            try:
                queued_ids = [
                    j.id for j in
                    db.query(AsyncJob)
                    .filter(AsyncJob.status == "queued")
                    .order_by(AsyncJob.created_at)
                    .limit(MAX_CONCURRENT_JOBS)
                    .all()
                ]
            finally:
                db.close()

            if queued_ids:
                await asyncio.gather(*(_process_job(jid) for jid in queued_ids))
        except Exception:  # noqa: BLE001 - the poll loop itself must never die
            logger.exception("Worker poll loop error")

        if asyncio.get_running_loop().time() - last_stale_check >= STALE_CHECK_SECONDS:
            await _requeue_stale_jobs_safely()
            last_stale_check = asyncio.get_running_loop().time()

        await asyncio.sleep(POLL_INTERVAL_SECONDS)


def start_worker() -> asyncio.Task:
    return asyncio.create_task(_poll_loop())
