from datetime import datetime

from sqlalchemy import Float, String, DateTime, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class WeatherObservation(Base):
    __tablename__ = "weather_observations"
    __table_args__ = (
        Index("ix_weather_observations_region_timestamp", "region_id", "timestamp"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    region_id: Mapped[int] = mapped_column(ForeignKey("regions.id"), nullable=False)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    temperature: Mapped[float] = mapped_column(Float, nullable=False)  # Fahrenheit
    humidity: Mapped[float] = mapped_column(Float, nullable=False)  # percent
    wind_speed: Mapped[float] = mapped_column(Float, nullable=False)  # mph
    weather_condition: Mapped[str] = mapped_column(String(50), nullable=False)

    region = relationship("Region", back_populates="weather_observations")
