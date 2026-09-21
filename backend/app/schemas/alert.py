from datetime import datetime
from pydantic import BaseModel, ConfigDict


class PeakAlertOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    region_id: int
    forecast_result_id: int
    risk_level: str
    predicted_load_mw: float
    capacity_mw: float
    message: str
    status: str
    created_at: datetime
