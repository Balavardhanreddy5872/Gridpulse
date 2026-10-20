from app import database


def test_health_ok(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"


# --- Milestone 5: two different probes -------------------------------------

def test_liveness_ok(client):
    r = client.get("/api/health/live")
    assert r.status_code == 200
    assert r.json()["status"] == "alive"
    assert r.json()["pod"]


def test_readiness_ok_when_database_answers(client):
    r = client.get("/api/health/ready")
    assert r.status_code == 200
    assert r.json() == {"status": "ready", "database": "ok", "pod": r.json()["pod"]}


def test_database_outage_fails_readiness_but_not_liveness(client, monkeypatch):
    """The whole point of the split: a database problem takes the pod OUT OF
    THE LOAD BALANCER (readiness 503) but must NOT get it restarted (liveness
    stays 200), otherwise every replica restarts at once."""
    def database_down():
        raise ConnectionError("could not connect to server: Connection timed out")

    monkeypatch.setattr(database, "check_database", database_down)

    ready = client.get("/api/health/ready")
    assert ready.status_code == 503
    assert ready.json()["status"] == "not ready"
    assert ready.json()["database"] == "error: ConnectionError"

    live = client.get("/api/health/live")
    assert live.status_code == 200


def test_slow_database_fails_readiness_within_the_time_limit(client, monkeypatch):
    import time

    from app.config import settings

    monkeypatch.setattr(settings, "READINESS_DB_TIMEOUT_SECONDS", 0.2)
    monkeypatch.setattr(database, "check_database", lambda: time.sleep(1))

    started = time.monotonic()
    r = client.get("/api/health/ready")
    assert r.status_code == 503
    assert "timeout" in r.json()["database"]
    assert time.monotonic() - started < 0.9   # answered before the DB call finished


def test_readiness_never_leaks_connection_details(client, monkeypatch):
    def database_down():
        raise RuntimeError("password authentication failed for user gridpulse at 10.60.0.3")

    monkeypatch.setattr(database, "check_database", database_down)
    body = client.get("/api/health/ready").text
    assert "10.60.0.3" not in body and "password" not in body
