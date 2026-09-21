from datetime import datetime
from pydantic import BaseModel, ConfigDict


class HourlyReadingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    region_id: int
    timestamp: datetime
    load_mw: float


class WeatherObservationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    region_id: int
    timestamp: datetime
    temperature: float
    humidity: float
    wind_speed: float
    weather_condition: str
