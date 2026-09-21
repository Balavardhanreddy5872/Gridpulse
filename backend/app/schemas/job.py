from datetime import datetime
from pydantic import BaseModel, ConfigDict


class AsyncJobOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    job_type: str
    region_id: int | None
    status: str
    created_at: datetime
    started_at: datetime | None = None
    completed_at: datetime | None = None
    error_message: str | None = None


class SpikeSimulationRequest(BaseModel):
    region_count: int = 10


class SpikeSimulationResponse(BaseModel):
    message: str
    jobs: list[AsyncJobOut]
