from datetime import datetime
from pydantic import BaseModel, ConfigDict


class ForecastResultOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    region_id: int
    forecast_timestamp: datetime
    predicted_load_mw: float
    effective_capacity_mw: float
    risk_level: str
    model_version: str
    created_at: datetime


class ForecastResponse(BaseModel):
    region_id: int
    region_name: str
    effective_capacity_mw: float
    model_version: str
    points: list[ForecastResultOut]
