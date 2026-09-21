from datetime import datetime
from pydantic import BaseModel, ConfigDict


class RegionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    state: str
    capacity_mw: float
    created_at: datetime


class RegionSummary(RegionOut):
    """Region plus a quick-glance risk status for the dashboard cards."""
    current_risk_level: str = "normal"
    active_alert_count: int = 0
