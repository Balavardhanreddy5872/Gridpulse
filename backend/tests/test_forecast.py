def test_forecast_falls_back_to_naive_without_trained_model(client, sample_region):
    """No model.joblib exists in the test environment, so this exercises
    the graceful fallback path required by the brief (never crash when
    the model file is missing)."""
    r = client.get(f"/api/regions/{sample_region.id}/forecast")
    assert r.status_code == 200
    body = r.json()
    assert body["model_version"] == "naive-v1"
    assert len(body["points"]) == 24
    assert body["effective_capacity_mw"] == sample_region.capacity_mw


def test_forecast_404_for_missing_region(client):
    r = client.get("/api/regions/999999/forecast")
    assert r.status_code == 404


def test_recompute_forecast_replaces_previous_points(client, sample_region):
    first = client.post(f"/api/forecast/{sample_region.id}").json()
    second = client.post(f"/api/forecast/{sample_region.id}").json()
    assert len(first["points"]) == len(second["points"]) == 24


def test_model_metrics_reports_untrained_state_honestly(client):
    r = client.get("/api/model/metrics")
    assert r.status_code == 200
    body = r.json()
    assert "model_version" in body
    assert "trained" in body
