"""Milestone 6: structured JSON logs, the controlled 5xx, and the release version.

The log-based metric gridpulse_http_5xx (terraform/monitoring.tf) counts log
entries by their jsonPayload fields, so these tests pin down the exact shape of
the request log entry the metric depends on."""
import json
import logging
import re
from pathlib import Path

import pytest

from app import database, models  # noqa: F401 - models registered before the tables are created
from app.logging_config import JsonFormatter, trace_fields

FORMATTER = JsonFormatter()
TERRAFORM_MONITORING = Path(__file__).resolve().parents[2] / "terraform" / "monitoring.tf"


def _entries(caplog, event=None):
    out = [json.loads(FORMATTER.format(r)) for r in caplog.records]
    return [e for e in out if event is None or e.get("event") == event]


@pytest.fixture()
def error_simulation(monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, "ENABLE_ERROR_SIMULATION", True)


def test_log_lines_are_single_line_json_with_cloud_logging_keys():
    record = logging.LogRecord("gridpulse.test", logging.WARNING, __file__, 10, "hello %s", ("world",), None)
    record.event = "unit_test"
    line = FORMATTER.format(record)
    assert "\n" not in line
    entry = json.loads(line)
    assert entry["severity"] == "WARNING"
    assert entry["message"] == "hello world"
    assert entry["event"] == "unit_test"
    assert entry["service"] == "gridpulse-backend"
    assert re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$", entry["time"])
    assert entry["logging.googleapis.com/sourceLocation"]["line"] == "10"


def test_exceptions_carry_a_stack_trace_for_error_reporting():
    try:
        raise ValueError("boom")
    except ValueError as exc:
        record = logging.LogRecord("gridpulse.test", logging.ERROR, __file__, 1, "failed", (), (type(exc), exc, exc.__traceback__))
    entry = json.loads(FORMATTER.format(record))
    assert entry["severity"] == "ERROR"
    assert "Traceback" in entry["stack_trace"] and "ValueError: boom" in entry["stack_trace"]
    assert entry["serviceContext"]["service"] == "gridpulse-backend"


def test_every_request_is_logged_once_as_json(client, caplog, sample_region):
    caplog.set_level(logging.INFO)
    r = client.get(f"/api/regions/{sample_region.id}", headers={"User-Agent": "pytest"})
    assert r.status_code == 200
    assert r.headers["X-Request-ID"]

    [entry] = _entries(caplog, "http_request")
    assert entry["severity"] == "INFO"
    assert entry["method"] == "GET"
    assert entry["path"] == f"/api/regions/{sample_region.id}"
    assert entry["route"] == "/api/regions/{region_id}"   # template: bounded label values
    assert entry["status_code"] == 200 and entry["status_class"] == "2xx"
    assert entry["probe"] is False
    assert entry["request_id"] == r.headers["X-Request-ID"]
    assert entry["httpRequest"]["status"] == 200
    assert re.match(r"^\d+\.\d{3}s$", entry["httpRequest"]["latency"])


def test_4xx_is_a_warning(client, caplog):
    caplog.set_level(logging.INFO)
    assert client.get("/api/regions/999999").status_code == 404
    [entry] = _entries(caplog, "http_request")
    assert entry["severity"] == "WARNING" and entry["status_code"] == 404


def test_error_simulation_is_off_unless_enabled(client):
    assert client.get("/api/system/simulate-error").status_code == 404


def test_controlled_500_is_logged_as_error_with_stack_trace(client, caplog, error_simulation):
    caplog.set_level(logging.INFO)
    r = client.get("/api/system/simulate-error")
    assert r.status_code == 500
    body = r.json()
    assert body["detail"] == "Unexpected server error: SimulatedFailure"
    assert body["request_id"] == r.headers["X-Request-ID"]

    [request_entry] = _entries(caplog, "http_request")
    assert request_entry["severity"] == "ERROR"
    assert request_entry["status_code"] == 500 and request_entry["status_class"] == "5xx"
    assert request_entry["route"] == "/api/system/simulate-error"

    [error_entry] = _entries(caplog, "unhandled_exception")
    assert error_entry["error_type"] == "SimulatedFailure"
    assert error_entry["request_id"] == request_entry["request_id"]
    assert "SimulatedFailure: Controlled failure" in error_entry["stack_trace"]


@pytest.mark.parametrize("status", [502, 503, 504])
def test_controlled_other_5xx(client, caplog, error_simulation, status):
    caplog.set_level(logging.INFO)
    assert client.get(f"/api/system/simulate-error?status={status}").status_code == status
    [entry] = _entries(caplog, "http_request")
    assert entry["status_code"] == status and entry["severity"] == "ERROR"


def test_only_5xx_codes_can_be_simulated(client, error_simulation):
    assert client.get("/api/system/simulate-error?status=200").status_code == 422


def test_successful_health_checks_are_not_logged(client, caplog):
    caplog.set_level(logging.INFO)
    for agent in ("kube-probe/1.33", "GoogleHC/1.0",
                  "GoogleStackdriverMonitoring-UptimeChecks(https://cloud.google.com/monitoring)"):
        assert client.get("/api/health/ready", headers={"User-Agent": agent}).status_code == 200
    assert _entries(caplog, "http_request") == []


def test_failing_probe_is_logged_but_marked_as_probe(client, caplog, monkeypatch):
    """A pod failing readiness stays visible in the logs, but probe traffic is
    kept out of the user-facing 5xx metric (probe=true)."""
    def database_down():
        raise ConnectionError("down")
    monkeypatch.setattr(database, "check_database", database_down)
    caplog.set_level(logging.INFO)
    assert client.get("/api/health/ready", headers={"User-Agent": "kube-probe/1.33"}).status_code == 503
    [entry] = _entries(caplog, "http_request")
    assert entry["probe"] is True and entry["status_code"] == 503


def test_version_endpoint(client):
    body = client.get("/api/version").json()
    assert body["service"] == "gridpulse-backend"
    assert body["version"]          # "dev" locally, the git commit in the cloud
    assert body["pod"]


def test_trace_header_becomes_cloud_logging_trace():
    assert trace_fields("105445aa7843bc8bf206b12000100000/1;o=1", "gridpulse-509202") == {
        "logging.googleapis.com/trace": "projects/gridpulse-509202/traces/105445aa7843bc8bf206b12000100000"
    }
    assert trace_fields(None, "gridpulse-509202") == {}


def test_untrusted_request_ids_are_replaced(client):
    r = client.get("/api/version", headers={"X-Request-ID": "x" * 500})
    assert len(r.headers["X-Request-ID"]) <= 64
    r = client.get("/api/version", headers={"X-Request-ID": "demo-123"})
    assert r.headers["X-Request-ID"] == "demo-123"


@pytest.mark.skipif(not TERRAFORM_MONITORING.exists(), reason="terraform/ not mounted")
def test_log_based_metric_uses_fields_the_app_actually_logs(client, caplog, error_simulation):
    """Contract test: every jsonPayload field the 5xx metric filters or labels
    on must exist in the request log entry."""
    caplog.set_level(logging.INFO)
    client.get("/api/system/simulate-error")
    [entry] = _entries(caplog, "http_request")
    tf = TERRAFORM_MONITORING.read_text()
    block = tf.split('resource "google_logging_metric" "http_5xx"', 1)[1].split('\nresource "', 1)[0]
    fields = set(re.findall(r"jsonPayload\.([a-z_]+)", block))
    assert {"event", "status_code", "probe"} <= fields
    for field in fields:
        assert field in entry, f"terraform uses jsonPayload.{field}, the app does not log it"
