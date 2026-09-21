def test_simulate_spike_creates_jobs_for_available_regions(client, sample_region):
    r = client.post("/api/jobs/simulate-spike", json={"region_count": 10})
    assert r.status_code == 200
    body = r.json()
    assert len(body["jobs"]) == 1  # only one region exists in this test DB
    assert body["jobs"][0]["status"] == "queued"


def test_simulate_spike_with_no_regions_returns_400(client):
    r = client.post("/api/jobs/simulate-spike", json={"region_count": 5})
    assert r.status_code == 400


def test_list_jobs_filters_by_status(client, sample_region):
    client.post("/api/jobs/simulate-spike", json={"region_count": 1})
    r = client.get("/api/jobs?status=queued")
    assert r.status_code == 200
    assert all(j["status"] == "queued" for j in r.json())
