from datetime import datetime, timezone

from sqlalchemy import Float, String, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class PeakAlert(Base):
    __tablename__ = "peak_alerts"

    id: Mapped[int] = mapped_column(primary_key=True)
    region_id: Mapped[int] = mapped_column(ForeignKey("regions.id"), nullable=False)
    forecast_result_id: Mapped[int] = mapped_column(
        ForeignKey("forecast_results.id"), nullable=False
    )
    risk_level: Mapped[str] = mapped_column(String(20), nullable=False)
    predicted_load_mw: Mapped[float] = mapped_column(Float, nullable=False)
    capacity_mw: Mapped[float] = mapped_column(Float, nullable=False)
    message: Mapped[str] = mapped_column(String(300), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="open")  # open/acknowledged/resolved
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    region = relationship("Region", back_populates="peak_alerts")
    forecast_result = relationship("ForecastResult", back_populates="peak_alerts")
