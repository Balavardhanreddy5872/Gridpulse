from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class InfrastructureDocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    region_id: int
    filename: str
    # where the PDF lives: gs://<bucket>/documents/... in the cloud
    storage_uri: str | None = Field(default=None, validation_alias="filepath")
    extracted_text: str | None = None
    capacity_impact_mw: float | None = None
    start_date: datetime | None = None
    end_date: datetime | None = None
    description: str | None = None
    uploaded_at: datetime
