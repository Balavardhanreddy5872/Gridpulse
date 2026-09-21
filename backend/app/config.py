"""
Central configuration for GridPulse backend.
All values are loaded from environment variables / .env, with safe local
defaults so the app can start immediately for a student demo.
"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str = "postgresql+psycopg2://gridpulse:gridpulse@localhost:5432/gridpulse"

    UPLOAD_DIRECTORY: str = "./uploads"
    MODEL_PATH: str = "./ml/model.joblib"

    CORS_ORIGINS: str = "http://localhost:5173,http://127.0.0.1:5173"

    # Risk thresholds - ratio of predicted_load_mw / effective_capacity_mw
    RISK_WATCH_PCT: float = 0.75
    RISK_HIGH_PCT: float = 0.85
    RISK_CRITICAL_PCT: float = 0.95

    FORECAST_HORIZON_HOURS: int = 24
    MAX_UPLOAD_MB: int = 10

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


settings = Settings()
