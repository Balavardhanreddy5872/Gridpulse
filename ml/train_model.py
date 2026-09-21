"""
GridPulse Stage 3 — trains the real short-term demand forecasting model.

Approach: XGBoost regression (falls back to RandomForest automatically if
xgboost isn't importable - see MODEL_CLASS below) trained on the seeded
synthetic dataset. Features are the standard demand-forecasting set:
calendar features, lagged load, rolling load stats, and weather.

This is intentionally a single global model across all regions (with
region as a one-hot feature) rather than one model per region - simpler
to train/serve/version, and with only 10 regions x 30 days of seed data
there isn't enough history per region to justify per-region models.

Usage:
    python ml/train_model.py

Reads from the same DATABASE_URL the backend uses (via backend/.env or
environment). Writes:
    ml/model.joblib   - trained model + feature metadata
    ml/metrics.json   - MAE / RMSE / MAPE on a held-out time window
"""
import json
import sys
from datetime import timedelta
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

_here = Path(__file__).resolve().parent
for _candidate in (_here.parent / "backend", Path("/app")):
    if (_candidate / "app" / "__init__.py").exists():
        sys.path.insert(0, str(_candidate))
        break
else:
    raise SystemExit("Could not locate backend/app - check your setup.")

from app.database import SessionLocal  # noqa: E402
from app.models import Region, HourlyReading, WeatherObservation  # noqa: E402

try:
    from xgboost import XGBRegressor
    MODEL_CLASS = "xgboost"
except ImportError:  # pragma: no cover - fallback path
    from sklearn.ensemble import RandomForestRegressor
    MODEL_CLASS = "random_forest"

from sklearn.metrics import mean_absolute_error, mean_squared_error

TEST_WINDOW_DAYS = 3  # most recent N days held out for evaluation
LAG_HOURS = [1, 24, 168]  # 1h, 1 day, 1 week
ROLLING_WINDOWS = [24]  # 24h rolling mean/std

MODEL_PATH = Path(__file__).resolve().parent / "model.joblib"
METRICS_PATH = Path(__file__).resolve().parent / "metrics.json"


def load_raw_data() -> pd.DataFrame:
    db = SessionLocal()
    try:
        regions = db.query(Region).all()
        readings = db.query(HourlyReading).order_by(HourlyReading.region_id, HourlyReading.timestamp).all()
        weather = db.query(WeatherObservation).order_by(WeatherObservation.region_id, WeatherObservation.timestamp).all()
    finally:
        db.close()

    if not readings:
        raise SystemExit("No hourly_readings found. Run scripts/seed_database.py first.")

    r_df = pd.DataFrame([{
        "region_id": r.region_id, "timestamp": r.timestamp, "load_mw": r.load_mw
    } for r in readings])
    w_df = pd.DataFrame([{
        "region_id": w.region_id, "timestamp": w.timestamp,
        "temperature": w.temperature, "humidity": w.humidity, "wind_speed": w.wind_speed,
    } for w in weather])
    region_capacity = {r.id: r.capacity_mw for r in regions}

    df = pd.merge(r_df, w_df, on=["region_id", "timestamp"], how="left")
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df["capacity_mw"] = df["region_id"].map(region_capacity)
    df = df.sort_values(["region_id", "timestamp"]).reset_index(drop=True)
    return df


def engineer_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["hour"] = df["timestamp"].dt.hour
    df["day_of_week"] = df["timestamp"].dt.dayofweek
    df["month"] = df["timestamp"].dt.month
    df["is_weekend"] = (df["day_of_week"] >= 5).astype(int)

    for lag in LAG_HOURS:
        df[f"lag_{lag}h"] = df.groupby("region_id")["load_mw"].shift(lag)

    for window in ROLLING_WINDOWS:
        df[f"rolling_mean_{window}h"] = (
            df.groupby("region_id")["load_mw"]
            .transform(lambda s: s.shift(1).rolling(window, min_periods=1).mean())
        )

    df["temperature"] = df["temperature"].fillna(df["temperature"].mean())
    df["humidity"] = df["humidity"].fillna(df["humidity"].mean())
    df["wind_speed"] = df["wind_speed"].fillna(df["wind_speed"].mean())

    region_dummies = pd.get_dummies(df["region_id"], prefix="region")
    df = pd.concat([df, region_dummies], axis=1)

    return df, list(region_dummies.columns)


def main():
    print(f"Loading data and training with model class: {MODEL_CLASS}")
    raw = load_raw_data()
    df, region_columns = engineer_features(raw)

    feature_columns = (
        ["hour", "day_of_week", "month", "is_weekend", "temperature", "humidity", "wind_speed"]
        + [f"lag_{lag}h" for lag in LAG_HOURS]
        + [f"rolling_mean_{w}h" for w in ROLLING_WINDOWS]
        + region_columns
    )

    df = df.dropna(subset=feature_columns + ["load_mw"]).reset_index(drop=True)
    if len(df) < 200:
        raise SystemExit(
            f"Only {len(df)} usable rows after feature engineering - need more seeded "
            f"history. Re-run scripts/seed_database.py with a longer window if needed."
        )

    cutoff = df["timestamp"].max() - timedelta(days=TEST_WINDOW_DAYS)
    train_df = df[df["timestamp"] <= cutoff]
    test_df = df[df["timestamp"] > cutoff]

    X_train, y_train = train_df[feature_columns], train_df["load_mw"]
    X_test, y_test = test_df[feature_columns], test_df["load_mw"]

    if MODEL_CLASS == "xgboost":
        model = XGBRegressor(
            n_estimators=300, max_depth=5, learning_rate=0.05,
            subsample=0.9, colsample_bytree=0.9, random_state=42,
        )
    else:
        model = RandomForestRegressor(n_estimators=300, max_depth=10, random_state=42, n_jobs=-1)

    model.fit(X_train, y_train)

    preds = model.predict(X_test)
    mae = mean_absolute_error(y_test, preds)
    rmse = float(np.sqrt(mean_squared_error(y_test, preds)))
    mape = float(np.mean(np.abs((y_test.values - preds) / np.clip(y_test.values, 1e-6, None))) * 100)

    print(f"Test rows: {len(test_df)} | MAE={mae:.2f} MW | RMSE={rmse:.2f} MW | MAPE={mape:.2f}%")

    joblib.dump({
        "model": model,
        "model_class": MODEL_CLASS,
        "feature_columns": feature_columns,
        "region_columns": region_columns,
        "lag_hours": LAG_HOURS,
        "rolling_windows": ROLLING_WINDOWS,
    }, MODEL_PATH)

    METRICS_PATH.write_text(json.dumps({
        "model_version": f"{MODEL_CLASS}-v1",
        "trained": True,
        "trained_at": pd.Timestamp.now("UTC").isoformat(),
        "mae_mw": round(mae, 2),
        "rmse_mw": round(rmse, 2),
        "mape_pct": round(mape, 2),
        "train_rows": len(train_df),
        "test_rows": len(test_df),
        "test_window_days": TEST_WINDOW_DAYS,
        "note": (
            f"{MODEL_CLASS} regressor trained on {LAG_HOURS} lag features + "
            f"{ROLLING_WINDOWS}h rolling mean + weather + calendar features, "
            "evaluated on the most recent held-out days of the seeded dataset."
        ),
    }, indent=2))

    print(f"Saved model to {MODEL_PATH}")
    print(f"Saved metrics to {METRICS_PATH}")


if __name__ == "__main__":
    main()
