import json
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Region, ForecastResult
from app.schemas.forecast import ForecastResponse, ForecastResultOut
from app.services.forecast_service import run_forecast

router = APIRouter(tags=["forecast"])


def _response_from(region: Region, created: list[ForecastResult]) -> ForecastResponse:
    return ForecastResponse(
        region_id=region.id,
        region_name=region.name,
        effective_capacity_mw=created[0].effective_capacity_mw,
        model_version=created[0].model_version,
        points=[ForecastResultOut.model_validate(fr) for fr in created],
    )


@router.get("/api/regions/{region_id}/forecast", response_model=ForecastResponse)
def get_forecast(region_id: int, db: Session = Depends(get_db)):
    region = db.get(Region, region_id)
    if not region:
        raise HTTPException(status_code=404, detail=f"Region {region_id} not found")

    existing = (
        db.query(ForecastResult)
        .filter(ForecastResult.region_id == region_id)
        .order_by(ForecastResult.forecast_timestamp)
        .all()
    )
    if not existing:
        created = run_forecast(db, region)
        return _response_from(region, created)

    return _response_from(region, existing)


@router.post("/api/forecast/{region_id}", response_model=ForecastResponse)
def recompute_forecast(region_id: int, db: Session = Depends(get_db)):
    region = db.get(Region, region_id)
    if not region:
        raise HTTPException(status_code=404, detail=f"Region {region_id} not found")
    created = run_forecast(db, region)
    return _response_from(region, created)


@router.get("/api/model/metrics")
def model_metrics():
    """
    Reports real MAE/RMSE/MAPE from ml/train_model.py's held-out
    evaluation once the model has been trained. Falls back to an honest
    "not trained yet" response instead of fabricating numbers.
    """
    metrics_path = Path(__file__).resolve().parent.parent.parent.parent / "ml" / "metrics.json"
    if metrics_path.exists():
        try:
            return json.loads(metrics_path.read_text())
        except Exception:
            pass
    return {
        "model_version": "naive-v1",
        "trained": False,
        "note": "No trained model found yet. Run `python ml/train_model.py` after "
                "seeding the database to train the real forecaster; until then, "
                "forecasts use a seasonal-naive baseline.",
    }
