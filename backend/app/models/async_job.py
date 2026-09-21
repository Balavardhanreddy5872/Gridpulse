from datetime import datetime, timezone

from sqlalchemy import String, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class AsyncJob(Base):
    __tablename__ = "async_jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    job_type: Mapped[str] = mapped_column(String(50), nullable=False)  # e.g. "forecast_recompute"
    region_id: Mapped[int] = mapped_column(ForeignKey("regions.id"), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="queued")
    # queued / processing / completed / failed
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    error_message: Mapped[str] = mapped_column(String(500), nullable=True)

    region = relationship("Region", back_populates="async_jobs")
