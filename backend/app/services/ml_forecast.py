"""
Stage 3 real forecaster. Loads the model trained by ml/train_model.py and
produces a recursive 24h-ahead forecast per region.

Recursive forecasting: at each future hour we need lag features (load
1h/24h/168h ago) and a 24h rolling mean. For lags that fall *before* the
forecast start, we pull real historical readings; for lags that fall
*within* the forecast horizon itself (e.g. predicting hour+2 needs
hour+1's value), we use our own just-generated predictions - this is the
standard recursive/autoregressive forecasting approach.

Future weather isn't available (no live weather feed in this project), so
weather features use the same seasonal-average proxy as the Stage 1 naive
baseline: the historical mean for that hour-of-day. This is a documented
simplification, not a silent approximation.

If no trained model is present yet (ml/model.joblib missing), this module
raises ModelNotAvailable and the caller (forecast router) falls back to
the Stage 1 naive baseline rather than crashing - see app.routers.forecast.
"""
from collections import defaultdict
from datetime import timedelta
from pathlib import Path

import joblib
import pandas as pd
from sqlalchemy.orm import Session

from app.config import settings
from app.models import HourlyReading, WeatherObservation, Region

_MODEL_CACHE = {}


class ModelNotAvailable(Exception):
    pass


def _model_path() -> Path:
    p = Path(settings.MODEL_PATH)
    if not p.is_absolute():
        # MODEL_PATH is relative to the backend/ working directory by
        # default; resolve relative to the repo root instead so it works
        # the same whether uvicorn is launched from backend/ or the root.
        p = Path(__file__).resolve().parent.parent.parent.parent / "ml" / "model.joblib"
    return p


def _load_bundle():
    path = _model_path()
    if not path.exists():
        raise ModelNotAvailable(f"No trained model at {path}. Run ml/train_model.py first.")
    key = str(path)
    if key not in _MODEL_CACHE:
        _MODEL_CACHE[key] = joblib.load(path)
    return _MODEL_CACHE[key]


def generate_ml_forecast(db: Session, region: Region, horizon_hours: int) -> list[tuple]:
    bundle = _load_bundle()
    model = bundle["model"]
    feature_columns = bundle["feature_columns"]
    region_columns = bundle["region_columns"]
    lag_hours = bundle["lag_hours"]
    rolling_windows = bundle["rolling_windows"]
    max_lag = max(lag_hours)

    readings = (
        db.query(HourlyReading)
        .filter(HourlyReading.region_id == region.id)
        .order_by(HourlyReading.timestamp.desc())
        .limit(max_lag + 24 * 10)
        .all()
    )
    if len(readings) < max_lag:
        raise ModelNotAvailable(
            f"Not enough history for region {region.id} to build lag features "
            f"({len(readings)} rows, need {max_lag})."
        )
    readings = list(reversed(readings))
    load_by_ts = {r.timestamp: r.load_mw for r in readings}
    last_ts = readings[-1].timestamp

    weather_hist = (
        db.query(WeatherObservation)
        .filter(WeatherObservation.region_id == region.id)
        .all()
    )
    weather_by_hour = defaultdict(list)
    for w in weather_hist:
        weather_by_hour[w.timestamp.hour].append((w.temperature, w.humidity, w.wind_speed))

    def seasonal_weather(hour: int):
        vals = weather_by_hour.get(hour)
        if not vals:
            return 75.0, 55.0, 8.0
        temps, hums, winds = zip(*vals)
        return sum(temps) / len(temps), sum(hums) / len(hums), sum(winds) / len(winds)

    region_row = {col: 0 for col in region_columns}
    region_key = f"region_{region.id}"
    if region_key in region_row:
        region_row[region_key] = 1

    predictions = []
    working_series = dict(load_by_ts)  # timestamp -> load, extended as we predict

    for h in range(1, horizon_hours + 1):
        ts = last_ts + timedelta(hours=h)
        temp, hum, wind = seasonal_weather(ts.hour)

        row = {
            "hour": ts.hour,
            "day_of_week": ts.weekday(),
            "month": ts.month,
            "is_weekend": int(ts.weekday() >= 5),
            "temperature": temp,
            "humidity": hum,
            "wind_speed": wind,
        }
        for lag in lag_hours:
            lag_ts = ts - timedelta(hours=lag)
            row[f"lag_{lag}h"] = working_series.get(lag_ts)

        for window in rolling_windows:
            recent = [
                working_series[ts - timedelta(hours=k)]
                for k in range(1, window + 1)
                if (ts - timedelta(hours=k)) in working_series
            ]
            row[f"rolling_mean_{window}h"] = (sum(recent) / len(recent)) if recent else None

        row.update(region_row)

        # If any lag/rolling feature is missing (sparse history), fall back
        # to the most recent known load rather than failing the whole
        # forecast for this one hour.
        fallback_load = readings[-1].load_mw
        for key in list(row.keys()):
            if row[key] is None:
                row[key] = fallback_load

        X = pd.DataFrame([row])[feature_columns]
        predicted = float(model.predict(X)[0])
        predicted = max(predicted, 0.0)

        working_series[ts] = predicted
        predictions.append((ts, round(predicted, 1)))

    return predictions
