"""
STAGE 1 PLACEHOLDER FORECASTER.

This is intentionally simple: a seasonal-naive baseline (average load for
the same hour-of-day and day-of-week across recent history, blended with
the most recent reading's trend). It exists so the API + dashboard have a
real, end-to-end working forecast to demo *today*.

In Stage 3 this will be swapped out for a trained XGBoost/RandomForest
model (see ml/train_model.py once added) without changing the API
contract - callers only need `generate_naive_forecast(...)`.
"""
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models import HourlyReading, Region


def generate_naive_forecast(db: Session, region: Region, horizon_hours: int) -> list[tuple]:
    """
    Returns a list of (timestamp, predicted_load_mw) tuples for the next
    `horizon_hours` hours, using a same-hour-of-week seasonal average.
    Falls back to the overall mean load if there isn't enough history yet.
    """
    readings = (
        db.query(HourlyReading)
        .filter(HourlyReading.region_id == region.id)
        .order_by(HourlyReading.timestamp.desc())
        .limit(24 * 30)  # last ~30 days
        .all()
    )

    if not readings:
        # No history at all yet - flat guess at 60% of capacity.
        base = region.capacity_mw * 0.6
        last_ts = None
    else:
        by_hour_of_week = defaultdict(list)
        for r in readings:
            key = (r.timestamp.weekday(), r.timestamp.hour)
            by_hour_of_week[key].append(r.load_mw)
        overall_mean = sum(r.load_mw for r in readings) / len(readings)
        last_ts = max(r.timestamp for r in readings)

    forecast_points = []
    start = last_ts or datetime.now(timezone.utc)
    for h in range(1, horizon_hours + 1):
        ts = start + timedelta(hours=h)
        if readings:
            key = (ts.weekday(), ts.hour)
            values = by_hour_of_week.get(key)
            predicted = (sum(values) / len(values)) if values else overall_mean
        else:
            predicted = base
        forecast_points.append((ts, round(predicted, 1)))

    return forecast_points
