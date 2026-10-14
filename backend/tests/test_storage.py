"""Milestone 4: uploads go to object storage, never to the VM's disk."""
import io

import pytest
from reportlab.pdfgen import canvas

from app.services import storage as storage_mod
from app.services.storage import GCSStorage, LocalStorage, object_name_for


def _pdf(text="Capacity reduction: 120 MW"):
    buf = io.BytesIO()
    c = canvas.Canvas(buf)
    c.drawString(100, 750, text)
    c.save()
    return buf.getvalue()


class FakeBlob:
    def __init__(self, bucket, name):
        self.bucket, self.name = bucket, name

    def upload_from_string(self, data, content_type=None, if_generation_match=None):
        assert if_generation_match == 0, "uploads must never overwrite an object"
        self.bucket.objects[self.name] = (data, content_type)

    def download_as_bytes(self):
        return self.bucket.objects[self.name][0]


class FakeBucket:
    def __init__(self):
        self.objects = {}

    def blob(self, name):
        return FakeBlob(self, name)


@pytest.fixture()
def fake_gcs(monkeypatch):
    gcs = GCSStorage("gridpulse-test-uploads", "documents")
    gcs.__dict__["_bucket"] = FakeBucket()  # replaces the cached real client
    monkeypatch.setattr(storage_mod, "get_storage", lambda: gcs)
    monkeypatch.setattr("app.routers.documents.get_storage", lambda: gcs)
    return gcs


def test_object_name_is_unique_and_safe():
    a = object_name_for(3, "../../etc/Sub station report (v2).pdf")
    b = object_name_for(3, "../../etc/Sub station report (v2).pdf")
    assert a != b
    assert a.startswith("region-3/")
    assert "/" not in a.split("/", 1)[1]
    assert " " not in a and ".." not in a


def test_local_storage_roundtrip(tmp_path):
    store = LocalStorage(str(tmp_path))
    uri = store.save("region-1/x.pdf", b"%PDF-1.4", "application/pdf")
    assert store.read(uri) == b"%PDF-1.4"


def test_upload_goes_to_bucket_not_disk(client, sample_region, fake_gcs, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    pdf = _pdf()
    r = client.post(
        "/api/documents/upload",
        data={"region_id": sample_region.id},
        files={"file": ("grid report.pdf", pdf, "application/pdf")},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["storage_uri"].startswith("gs://gridpulse-test-uploads/documents/region-")
    assert body["capacity_impact_mw"] == 120.0  # text extracted from in-memory bytes

    objects = fake_gcs._bucket.objects
    assert len(objects) == 1
    (name, (data, ctype)), = objects.items()
    assert data == pdf and ctype == "application/pdf"
    assert not any(tmp_path.iterdir()), "nothing may be written to local disk"

    # the app can read the file back from the bucket
    r = client.get(f"/api/documents/{body['id']}/file")
    assert r.status_code == 200
    assert r.content == pdf


def test_storage_failure_returns_502(client, sample_region, monkeypatch):
    class Broken:
        def save(self, *a, **k):
            raise storage_mod.StorageError("403 Forbidden")

    monkeypatch.setattr("app.routers.documents.get_storage", lambda: Broken())
    r = client.post(
        "/api/documents/upload",
        data={"region_id": sample_region.id},
        files={"file": ("r.pdf", _pdf(), "application/pdf")},
    )
    assert r.status_code == 502
    assert "403" in r.json()["detail"]
