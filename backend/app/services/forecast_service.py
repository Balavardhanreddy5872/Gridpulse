"""
Shared forecast-running logic used by both the /forecast API endpoints
and the async worker (app.workers.spike_worker), so a queued
"forecast_recompute" job does exactly the same thing a manual
POST /api/forecast/{id} call does.
"""
import json
from pathlib import Path

from sqlalchemy.orm import Session

from app.config import settings
from app.models import Region, ForecastResult, PeakAlert
from app.services.forecast_baseline import generate_naive_forecast
from app.services.ml_forecast import generate_ml_forecast, ModelNotAvailable
from app.services.risk_engine import compute_effective_capacity, compute_risk_level, maybe_create_alert


def _generate_points(db: Session, region: Region):
    """Try the trained ML model first; fall back to the naive seasonal
    baseline if no model is trained yet or there isn't enough history."""
    try:
        points = generate_ml_forecast(db, region, settings.FORECAST_HORIZON_HOURS)
        return points, _model_version()
    except ModelNotAvailable:
        points = generate_naive_forecast(db, region, settings.FORECAST_HORIZON_HOURS)
        return points, "naive-v1"


def _model_version() -> str:
    metrics_path = Path(__file__).resolve().parent.parent.parent.parent / "ml" / "metrics.json"
    if metrics_path.exists():
        try:
            return json.loads(metrics_path.read_text()).get("model_version", "trained-v1")
        except Exception:
            return "trained-v1"
    return "trained-v1"


def run_forecast(db: Session, region: Region) -> list[ForecastResult]:
    """
    Recomputes and persists the forecast for one region: clears its old
    forecast rows, generates new ones (ML if available, else naive),
    computes risk per point, and raises PeakAlerts where warranted.
    Returns the list of newly-created ForecastResult rows (already
    committed and refreshed).
    """
    effective_capacity = compute_effective_capacity(db, region)
    points, model_version = _generate_points(db, region)

    old_ids = [row.id for row in db.query(ForecastResult.id).filter(ForecastResult.region_id == region.id)]
    if old_ids:
        db.query(PeakAlert).filter(PeakAlert.forecast_result_id.in_(old_ids)).delete(synchronize_session=False)
    db.query(ForecastResult).filter(ForecastResult.region_id == region.id).delete()

    created = []
    for ts, predicted in points:
        risk_level = compute_risk_level(predicted, effective_capacity)
        fr = ForecastResult(
            region_id=region.id,
            forecast_timestamp=ts,
            predicted_load_mw=predicted,
            effective_capacity_mw=effective_capacity,
            risk_level=risk_level,
            model_version=model_version,
        )
        db.add(fr)
        db.flush()
        maybe_create_alert(db, fr, region)
        created.append(fr)

    db.commit()
    for fr in created:
        db.refresh(fr)
    return created
