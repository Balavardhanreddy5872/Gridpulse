from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Region, HourlyReading, PeakAlert
from app.schemas.region import RegionOut, RegionSummary
from app.schemas.reading import HourlyReadingOut
from app.services.risk_engine import compute_effective_capacity, compute_risk_level

router = APIRouter(prefix="/api/regions", tags=["regions"])


@router.get("", response_model=list[RegionSummary])
def list_regions(db: Session = Depends(get_db)):
    regions = db.query(Region).order_by(Region.name).all()
    out = []
    for r in regions:
        open_alerts = (
            db.query(PeakAlert)
            .filter(PeakAlert.region_id == r.id, PeakAlert.status == "open")
            .all()
        )
        worst = "normal"
        order = {"normal": 0, "watch": 1, "high": 2, "critical": 3}
        for a in open_alerts:
            if order.get(a.risk_level, 0) > order.get(worst, 0):
                worst = a.risk_level
        summary = RegionSummary.model_validate(r)
        summary.current_risk_level = worst
        summary.active_alert_count = len(open_alerts)
        out.append(summary)
    return out


@router.get("/{region_id}", response_model=RegionOut)
def get_region(region_id: int, db: Session = Depends(get_db)):
    region = db.get(Region, region_id)
    if not region:
        raise HTTPException(status_code=404, detail=f"Region {region_id} not found")
    return region


@router.get("/{region_id}/readings", response_model=list[HourlyReadingOut])
def get_region_readings(region_id: int, hours: int = 168, db: Session = Depends(get_db)):
    region = db.get(Region, region_id)
    if not region:
        raise HTTPException(status_code=404, detail=f"Region {region_id} not found")
    readings = (
        db.query(HourlyReading)
        .filter(HourlyReading.region_id == region_id)
        .order_by(HourlyReading.timestamp.desc())
        .limit(hours)
        .all()
    )
    return list(reversed(readings))
