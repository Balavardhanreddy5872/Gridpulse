"""
Peak-risk engine.

Converts a predicted load + effective capacity into a risk level using
configurable thresholds (see app.config.settings). Thresholds are ratios
of predicted_load_mw / effective_capacity_mw:

    ratio < RISK_WATCH_PCT        -> normal
    ratio < RISK_HIGH_PCT         -> watch
    ratio < RISK_CRITICAL_PCT     -> high
    ratio >= RISK_CRITICAL_PCT    -> critical
"""
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Region, InfrastructureDocument, PeakAlert, ForecastResult


def compute_risk_level(predicted_load_mw: float, effective_capacity_mw: float) -> str:
    if effective_capacity_mw <= 0:
        return "critical"
    ratio = predicted_load_mw / effective_capacity_mw
    if ratio >= settings.RISK_CRITICAL_PCT:
        return "critical"
    if ratio >= settings.RISK_HIGH_PCT:
        return "high"
    if ratio >= settings.RISK_WATCH_PCT:
        return "watch"
    return "normal"


def compute_effective_capacity(db: Session, region: Region, at_time: datetime | None = None) -> float:
    """
    Base region capacity minus any currently-active infrastructure impacts
    (e.g. a transformer under maintenance) whose [start_date, end_date]
    window covers `at_time`.
    """
    at_time = at_time or datetime.now(timezone.utc)

    docs = (
        db.query(InfrastructureDocument)
        .filter(InfrastructureDocument.region_id == region.id)
        .filter(InfrastructureDocument.capacity_impact_mw.isnot(None))
        .all()
    )

    def _as_utc(dt):
        """PDF/form-parsed dates come in naive; normalize to UTC-aware so
        they can be safely compared against `at_time`."""
        if dt is None:
            return None
        return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)

    total_impact = 0.0
    for doc in docs:
        start = _as_utc(doc.start_date)
        end = _as_utc(doc.end_date)
        starts_ok = start is None or start <= at_time
        ends_ok = end is None or end >= at_time
        if starts_ok and ends_ok:
            total_impact += doc.capacity_impact_mw or 0.0

    effective = region.capacity_mw - total_impact
    return max(effective, 0.0)


def risk_message(region_name: str, risk_level: str, predicted: float, capacity: float, when: datetime) -> str:
    when_str = when.strftime("%Y-%m-%d %H:%M UTC")
    return (
        f"{region_name}: {risk_level.upper()} risk at {when_str} - "
        f"forecasted {predicted:.0f} MW vs effective capacity {capacity:.0f} MW"
    )


def maybe_create_alert(db: Session, forecast: ForecastResult, region: Region) -> PeakAlert | None:
    """Create a PeakAlert row if the forecast risk level warrants one (watch or above)."""
    if forecast.risk_level == "normal":
        return None

    alert = PeakAlert(
        region_id=region.id,
        forecast_result_id=forecast.id,
        risk_level=forecast.risk_level,
        predicted_load_mw=forecast.predicted_load_mw,
        capacity_mw=forecast.effective_capacity_mw,
        message=risk_message(
            region.name, forecast.risk_level, forecast.predicted_load_mw,
            forecast.effective_capacity_mw, forecast.forecast_timestamp,
        ),
        status="open",
    )
    db.add(alert)
    return alert
