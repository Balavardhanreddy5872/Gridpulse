from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import PeakAlert, Region
from app.schemas.alert import PeakAlertOut

router = APIRouter(tags=["alerts"])


@router.get("/api/alerts", response_model=list[PeakAlertOut])
def list_alerts(status: str | None = None, db: Session = Depends(get_db)):
    query = db.query(PeakAlert)
    if status:
        query = query.filter(PeakAlert.status == status)
    return query.order_by(PeakAlert.created_at.desc()).all()


@router.get("/api/regions/{region_id}/alerts", response_model=list[PeakAlertOut])
def list_region_alerts(region_id: int, db: Session = Depends(get_db)):
    region = db.get(Region, region_id)
    if not region:
        raise HTTPException(status_code=404, detail=f"Region {region_id} not found")
    return (
        db.query(PeakAlert)
        .filter(PeakAlert.region_id == region_id)
        .order_by(PeakAlert.created_at.desc())
        .all()
    )
