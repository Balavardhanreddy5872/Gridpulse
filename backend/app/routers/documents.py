import os
import shutil
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import Region, InfrastructureDocument
from app.schemas.document import InfrastructureDocumentOut
from app.services.pdf_service import extract_text, auto_extract_fields

router = APIRouter(tags=["documents"])

ALLOWED_EXTENSIONS = {".pdf"}


@router.post("/api/documents/upload", response_model=InfrastructureDocumentOut)
async def upload_document(
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

    contents = await file.read()
    max_bytes = settings.MAX_UPLOAD_MB * 1024 * 1024
    if len(contents) > max_bytes:
        raise HTTPException(status_code=400, detail=f"File exceeds {settings.MAX_UPLOAD_MB}MB limit")

    os.makedirs(settings.UPLOAD_DIRECTORY, exist_ok=True)
    safe_name = f"{uuid.uuid4().hex}_{os.path.basename(file.filename)}"
    filepath = os.path.join(settings.UPLOAD_DIRECTORY, safe_name)
    with open(filepath, "wb") as f:
        f.write(contents)

    try:
        text = extract_text(filepath)
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
        filepath=filepath,
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
