import io
import os
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import Region, InfrastructureDocument
from app.schemas.document import InfrastructureDocumentOut
from app.services.pdf_service import extract_text, auto_extract_fields
from app.services.storage import StorageError, get_storage, object_name_for

router = APIRouter(tags=["documents"])

ALLOWED_EXTENSIONS = {".pdf"}


# A plain `def` (not `async def`): FastAPI then runs it in a worker thread, so
# the database calls, the upload to Cloud Storage and the PDF text extraction
# never block the event loop that answers the other requests and the probes.
@router.post("/api/documents/upload", response_model=InfrastructureDocumentOut)
def upload_document(
    region_id: int = Form(...),
    capacity_impact_mw: float | None = Form(None),
    start_date: str | None = Form(None),
    end_date: str | None = Form(None),
    description: str | None = Form(None),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    region = db.get(Region, region_id)
    if not region:
        raise HTTPException(status_code=404, detail=f"Region {region_id} not found")

    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Only PDF files are accepted")

    contents = file.file.read()
    max_bytes = settings.MAX_UPLOAD_MB * 1024 * 1024
    if len(contents) > max_bytes:
        raise HTTPException(status_code=400, detail=f"File exceeds {settings.MAX_UPLOAD_MB}MB limit")

    # Milestone 4: the PDF goes straight from memory to the storage bucket
    # (gs://...) - it is never written to the VM's disk. Text extraction
    # also works on the in-memory bytes.
    try:
        stored_uri = get_storage().save(
            object_name_for(region_id, file.filename), contents, "application/pdf"
        )
    except StorageError as exc:
        raise HTTPException(status_code=502, detail=f"Could not store the file: {exc}") from exc

    try:
        text = extract_text(io.BytesIO(contents))
    except Exception:
        text = ""

    auto = auto_extract_fields(text)

    def parse_form_date(raw: str | None):
        if not raw:
            return None
        for fmt in ("%Y-%m-%d", "%m/%d/%Y"):
            try:
                return datetime.strptime(raw, fmt)
            except ValueError:
                continue
        return None

    doc = InfrastructureDocument(
        region_id=region_id,
        filename=file.filename,
        filepath=stored_uri,
        extracted_text=text,
        capacity_impact_mw=capacity_impact_mw if capacity_impact_mw is not None else auto["capacity_impact_mw"],
        start_date=parse_form_date(start_date) or auto["start_date"],
        end_date=parse_form_date(end_date) or auto["end_date"],
        description=description or auto["description"],
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


@router.get("/api/documents", response_model=list[InfrastructureDocumentOut])
def list_documents(region_id: int | None = None, db: Session = Depends(get_db)):
    query = db.query(InfrastructureDocument)
    if region_id is not None:
        query = query.filter(InfrastructureDocument.region_id == region_id)
    return query.order_by(InfrastructureDocument.uploaded_at.desc()).all()


@router.get("/api/documents/{document_id}/file")
def download_document(document_id: int, db: Session = Depends(get_db)):
    """Stream the original PDF back from wherever it is stored (the bucket in the cloud)."""
    doc = db.get(InfrastructureDocument, document_id)
    if not doc:
        raise HTTPException(status_code=404, detail=f"Document {document_id} not found")
    try:
        data = get_storage().read(doc.filepath)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"Could not read {doc.filepath}: {exc}") from exc
    safe_name = os.path.basename(doc.filename or "document.pdf").replace('"', "")
    return Response(
        content=data,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{safe_name}"'},
    )
