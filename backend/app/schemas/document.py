from datetime import datetime
from pydantic import BaseModel, ConfigDict


class InfrastructureDocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    region_id: int
    filename: str
    extracted_text: str | None = None
    capacity_impact_mw: float | None = None
    start_date: datetime | None = None
    end_date: datetime | None = None
    description: str | None = None
    uploaded_at: datetime
