from datetime import datetime, timedelta, timezone

from app.models import AsyncJob
from app.workers.spike_worker import requeue_stale_jobs


def test_stale_processing_jobs_are_requeued(db_session, sample_region):
    old = datetime.now(timezone.utc) - timedelta(minutes=30)
    recent = datetime.now(timezone.utc) - timedelta(seconds=10)
    stuck = AsyncJob(job_type="forecast_recompute", region_id=sample_region.id, status="processing", started_at=old)
    busy = AsyncJob(job_type="forecast_recompute", region_id=sample_region.id, status="processing", started_at=recent)
    db_session.add_all([stuck, busy])
    db_session.commit()

    assert requeue_stale_jobs() == 1
    db_session.expire_all()
    assert db_session.get(AsyncJob, stuck.id).status == "queued"
    assert db_session.get(AsyncJob, busy.id).status == "processing"
