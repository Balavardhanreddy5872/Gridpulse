from datetime import datetime, timezone

from sqlalchemy import String, Float, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Region(Base):
    __tablename__ = "regions"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    state: Mapped[str] = mapped_column(String(50), nullable=False)
    capacity_mw: Mapped[float] = mapped_column(Float, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    hourly_readings = relationship(
        "HourlyReading", back_populates="region", cascade="all, delete-orphan"
    )
    weather_observations = relationship(
        "WeatherObservation", back_populates="region", cascade="all, delete-orphan"
    )
    forecast_results = relationship(
        "ForecastResult", back_populates="region", cascade="all, delete-orphan"
    )
    peak_alerts = relationship(
        "PeakAlert", back_populates="region", cascade="all, delete-orphan"
    )
    infrastructure_documents = relationship(
        "InfrastructureDocument", back_populates="region", cascade="all, delete-orphan"
    )
    async_jobs = relationship("AsyncJob", back_populates="region")
