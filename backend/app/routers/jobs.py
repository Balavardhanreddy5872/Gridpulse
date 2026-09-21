"""
Async-job endpoints. Jobs are created here with status="queued"; the
background worker (app.workers.spike_worker, started in app.main on
FastAPI startup) polls for queued jobs and processes several
concurrently, moving each through queued -> processing ->
completed/failed. See app/workers/spike_worker.py for the poll loop.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import AsyncJob, Region
from app.schemas.job import AsyncJobOut, SpikeSimulationRequest, SpikeSimulationResponse

router = APIRouter(tags=["jobs"])


@router.get("/api/jobs", response_model=list[AsyncJobOut])
def list_jobs(status: str | None = None, db: Session = Depends(get_db)):
    query = db.query(AsyncJob)
    if status:
        query = query.filter(AsyncJob.status == status)
    return query.order_by(AsyncJob.created_at.desc()).limit(200).all()


@router.get("/api/jobs/{job_id}", response_model=AsyncJobOut)
def get_job(job_id: int, db: Session = Depends(get_db)):
    job = db.get(AsyncJob, job_id)
    if not job:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    return job


@router.post("/api/jobs/simulate-spike", response_model=SpikeSimulationResponse)
def simulate_spike(payload: SpikeSimulationRequest, db: Session = Depends(get_db)):
    regions = db.query(Region).limit(payload.region_count).all()
    if not regions:
        raise HTTPException(status_code=400, detail="No regions exist yet - seed the database first")

    jobs = []
    for region in regions:
        job = AsyncJob(job_type="forecast_recompute", region_id=region.id, status="queued")
        db.add(job)
        jobs.append(job)
    db.commit()
    for job in jobs:
        db.refresh(job)

    return SpikeSimulationResponse(
        message=(
            f"{len(jobs)} forecast-recompute jobs queued. The background worker "
            f"picks up to {3} at a time and processes them concurrently - watch "
            "their status move queued -> processing -> completed below."
        ),
        jobs=jobs,
    )
