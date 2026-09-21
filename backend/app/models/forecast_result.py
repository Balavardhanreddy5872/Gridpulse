from datetime import datetime, timezone

from sqlalchemy import Float, String, DateTime, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class ForecastResult(Base):
    __tablename__ = "forecast_results"
    __table_args__ = (
        Index("ix_forecast_results_region_ts", "region_id", "forecast_timestamp"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    region_id: Mapped[int] = mapped_column(ForeignKey("regions.id"), nullable=False)
    forecast_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    predicted_load_mw: Mapped[float] = mapped_column(Float, nullable=False)
    effective_capacity_mw: Mapped[float] = mapped_column(Float, nullable=False)
    risk_level: Mapped[str] = mapped_column(String(20), nullable=False)  # normal/watch/high/critical
    model_version: Mapped[str] = mapped_column(String(50), nullable=False, default="naive-v1")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    region = relationship("Region", back_populates="forecast_results")
    peak_alerts = relationship("PeakAlert", back_populates="forecast_result")
