def test_list_regions_empty_then_populated(client, sample_region):
    r = client.get("/api/regions")
    assert r.status_code == 200
    names = [region["name"] for region in r.json()]
    assert "Test Region" in names


def test_get_region_404(client):
    r = client.get("/api/regions/999999")
    assert r.status_code == 404


def test_get_region_readings_empty_region_returns_empty_list(client, sample_region):
    r = client.get(f"/api/regions/{sample_region.id}/readings")
    assert r.status_code == 200
    assert r.json() == []
