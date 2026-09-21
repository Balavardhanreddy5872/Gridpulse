import io

from reportlab.pdfgen import canvas


def _make_pdf_bytes(lines):
    buf = io.BytesIO()
    c = canvas.Canvas(buf)
    y = 750
    for line in lines:
        c.drawString(100, y, line)
        y -= 30
    c.save()
    buf.seek(0)
    return buf.read()


def test_upload_extracts_capacity_and_dates(client, sample_region):
    pdf_bytes = _make_pdf_bytes([
        "GridPulse Infrastructure Inspection Report",
        f"Region: {sample_region.name}",
        "Capacity reduction: 150 MW",
        "Maintenance window: 2026-01-10 to 2026-01-15",
    ])
    r = client.post(
        "/api/documents/upload",
        data={"region_id": sample_region.id},
        files={"file": ("report.pdf", pdf_bytes, "application/pdf")},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["capacity_impact_mw"] == 150.0
    assert body["start_date"].startswith("2026-01-10")
    assert body["end_date"].startswith("2026-01-15")


def test_upload_rejects_non_pdf(client, sample_region):
    r = client.post(
        "/api/documents/upload",
        data={"region_id": sample_region.id},
        files={"file": ("notes.txt", b"hello", "text/plain")},
    )
    assert r.status_code == 400


def test_upload_manual_override_wins_over_auto_extraction(client, sample_region):
    pdf_bytes = _make_pdf_bytes(["Capacity reduction: 150 MW"])
    r = client.post(
        "/api/documents/upload",
        data={"region_id": sample_region.id, "capacity_impact_mw": 999},
        files={"file": ("report2.pdf", pdf_bytes, "application/pdf")},
    )
    assert r.status_code == 200
    assert r.json()["capacity_impact_mw"] == 999.0
