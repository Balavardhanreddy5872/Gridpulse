"""
Seeds the GridPulse database with SYNTHETIC demo data modeled loosely on
the structure of the PJM Hourly Energy Consumption dataset (NOT real PJM
data - clearly labeled here and in the README). Produces:

  - 10 regions with realistic-looking names/capacities
  - 30 days of hourly load readings per region, with daily + weekly
    seasonality, a summer-heat-wave-style spike baked into one region,
    and random noise
  - matching weather observations (temperature drives load up in the
    synthetic model, mimicking real AC-driven demand)

Run with:  python scripts/seed_database.py
(from the backend/ virtualenv, with DATABASE_URL configured)
"""
import math
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

_here = Path(__file__).resolve().parent
for _candidate in (_here.parent / "backend", Path("/app")):
    if (_candidate / "app" / "__init__.py").exists():
        sys.path.insert(0, str(_candidate))
        break
else:
    raise SystemExit("Could not locate backend/app - check your setup.")

from app.database import Base, engine, SessionLocal  # noqa: E402
from app.models import Region, HourlyReading, WeatherObservation  # noqa: E402

random.seed(42)

REGIONS = [
    ("North Houston", "TX", 1200),
    ("South Houston", "TX", 950),
    ("Austin Metro", "TX", 800),
    ("Dallas Central", "TX", 1500),
    ("San Antonio West", "TX", 700),
    ("Oklahoma City", "OK", 600),
    ("Tulsa", "OK", 450),
    ("Baton Rouge", "LA", 500),
    ("New Orleans", "LA", 650),
    ("Shreveport", "LA", 380),
]

DAYS_OF_HISTORY = 30
HEAT_WAVE_REGION = "North Houston"  # this region gets a synthetic demand spike


def synthetic_load(base_capacity: float, ts: datetime, region_name: str) -> float:
    hour = ts.hour
    weekday = ts.weekday()  # 0=Mon .. 6=Sun

    # Daily curve: low overnight, peaks in the evening (~18:00-20:00).
    daily_factor = 0.55 + 0.35 * math.sin((hour - 6) / 24 * 2 * math.pi) ** 2
    if 17 <= hour <= 20:
        daily_factor += 0.15

    # Weekday demand is a bit higher than weekend.
    weekday_factor = 1.0 if weekday < 5 else 0.85

    load = base_capacity * daily_factor * weekday_factor

    # Bake in a multi-day heat-wave spike for one region, 1-3 days back in
    # the seeded history, so the last-96-hours chart has an obvious spike
    # to point at during the demo. Note: because this is *historical* data
    # (there's no future weather input in the Stage 1 naive forecaster),
    # this spike shows up in the historical chart, not automatically in
    # the forward-looking forecast. The forecast side of the demo is
    # driven deterministically by the infrastructure-PDF capacity
    # reduction instead (see documents workflow) - that's the guaranteed
    # peak-risk trigger for the walkthrough.
    if region_name == HEAT_WAVE_REGION:
        days_from_now = (datetime.now(timezone.utc) - ts).days
        if 1 <= days_from_now <= 3:
            load *= 1.35

    load *= random.uniform(0.95, 1.05)  # noise
    return round(load, 1)


def synthetic_weather(ts: datetime, region_name: str) -> dict:
    hour = ts.hour
    base_temp = 78 + 12 * math.sin((hour - 9) / 24 * 2 * math.pi)  # F, peaks midafternoon
    if region_name == HEAT_WAVE_REGION:
        days_from_now = (datetime.now(timezone.utc) - ts).days
        if 1 <= days_from_now <= 3:
            base_temp += 10
    temperature = round(base_temp + random.uniform(-2, 2), 1)
    humidity = round(random.uniform(40, 85), 1)
    wind_speed = round(random.uniform(2, 18), 1)
    condition = random.choice(["Clear", "Partly Cloudy", "Cloudy", "Rain", "Hot"])
    return {
        "temperature": temperature,
        "humidity": humidity,
        "wind_speed": wind_speed,
        "weather_condition": condition,
    }


def main():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()

    try:
        existing = db.query(Region).count()
        if existing > 0:
            print(f"Database already has {existing} regions - skipping seed. "
                  f"Delete rows manually or drop the DB to reseed.")
            return

        regions = []
        for name, state, capacity in REGIONS:
            region = Region(name=name, state=state, capacity_mw=capacity)
            db.add(region)
            regions.append(region)
        db.commit()
        for r in regions:
            db.refresh(r)

        now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
        start = now - timedelta(days=DAYS_OF_HISTORY)
        total_hours = DAYS_OF_HISTORY * 24

        for region in regions:
            readings = []
            weathers = []
            for h in range(total_hours):
                ts = start + timedelta(hours=h)
                readings.append(HourlyReading(
                    region_id=region.id,
                    timestamp=ts,
                    load_mw=synthetic_load(region.capacity_mw, ts, region.name),
                ))
                weathers.append(WeatherObservation(
                    region_id=region.id,
                    timestamp=ts,
                    **synthetic_weather(ts, region.name),
                ))
            db.bulk_save_objects(readings)
            db.bulk_save_objects(weathers)
            print(f"Seeded {len(readings)} hourly readings + weather rows for {region.name}")

        db.commit()
        print(f"\nDone. Seeded {len(regions)} regions x {total_hours} hours "
              f"({len(regions) * total_hours} readings total).")
        print(f"NOTE: This is SYNTHETIC demo data modeled on PJM's structure, "
              f"not the real PJM dataset. '{HEAT_WAVE_REGION}' has a baked-in "
              f"heat-wave spike 1-3 days ago in its historical readings "
              f"(visible on its load chart). For a guaranteed peak-risk alert "
              f"in the forecast itself, upload an infrastructure PDF for a "
              f"region with a maintenance window covering today - see the "
              f"Documents page.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
