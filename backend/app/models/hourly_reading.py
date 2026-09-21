from datetime import datetime

from sqlalchemy import Float, DateTime, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class HourlyReading(Base):
    __tablename__ = "hourly_readings"
    __table_args__ = (
        Index("ix_hourly_readings_region_timestamp", "region_id", "timestamp"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    region_id: Mapped[int] = mapped_column(ForeignKey("regions.id"), nullable=False)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    load_mw: Mapped[float] = mapped_column(Float, nullable=False)

    region = relationship("Region", back_populates="hourly_readings")
