"""Milestone 5: several backend replicas share one job queue in Cloud SQL."""
from app.database import SessionLocal
from app.models import AsyncJob
from app.workers.spike_worker import claim_job


def test_a_job_can_be_claimed_only_once(db_session, sample_region):
    job = AsyncJob(job_type="forecast_recompute", region_id=sample_region.id, status="queued")
    db_session.add(job)
    db_session.commit()

    replica_a, replica_b = SessionLocal(), SessionLocal()
    try:
        assert claim_job(replica_a, job.id) is True    # first replica wins
        assert claim_job(replica_b, job.id) is False   # second one gets nothing
    finally:
        replica_a.close()
        replica_b.close()

    db_session.expire_all()
    claimed = db_session.get(AsyncJob, job.id)
    assert claimed.status == "processing"
    assert claimed.started_at is not None


def test_finished_jobs_are_never_claimed_again(db_session, sample_region):
    done = AsyncJob(job_type="forecast_recompute", region_id=sample_region.id, status="completed")
    db_session.add(done)
    db_session.commit()
    assert claim_job(db_session, done.id) is False


def test_system_info_names_the_pod(client, monkeypatch):
    monkeypatch.setenv("POD_NAME", "backend-7d9f-abcde")
    monkeypatch.setenv("NODE_NAME", "gk3-gridpulse-pool-1")
    served_by = client.get("/api/system/info").json()["served_by"]
    assert served_by["pod"] == "backend-7d9f-abcde"
    assert served_by["node"] == "gk3-gridpulse-pool-1"


def test_request_threads_are_capped_per_pod(client):
    """Milestone 5: each pod works on at most REQUEST_THREADS requests at once,
    so under load the liveness probe still gets CPU and nobody waits 30 s for
    one of the pod's 3 database connections."""
    import anyio.to_thread

    from app.config import settings

    tokens = client.portal.call(lambda: anyio.to_thread.current_default_thread_limiter().total_tokens)
    assert tokens == settings.REQUEST_THREADS == 4


def test_worker_poll_query_runs_off_the_event_loop(db_session, sample_region):
    """The poll query is a plain function the worker calls via asyncio.to_thread,
    so a pod waiting for a DB connection never freezes its probes."""
    import inspect

    from app.workers import spike_worker

    job = AsyncJob(job_type="forecast_recompute", region_id=sample_region.id, status="queued")
    db_session.add(job)
    db_session.commit()

    assert not inspect.iscoroutinefunction(spike_worker.queued_job_ids)
    assert spike_worker.queued_job_ids() == [job.id]
    assert "to_thread(queued_job_ids)" in inspect.getsource(spike_worker._poll_loop)
