"""
Central configuration for the GridPulse backend.

Milestone 4 rule: this file holds NO secrets and the app never reads a .env
file. Every value comes from an environment variable set by docker compose
(or by your shell for native development).

Two ways to reach the database:

  * Cloud (the VM):  DB_PASSWORD_SECRET names a Google Secret Manager secret.
                     The password is fetched at start-up with the VM's service
                     account and held only in memory. The host is the Cloud SQL
                     instance's PRIVATE IP, looked up from CLOUDSQL_INSTANCE
                     (or given directly as DB_HOST).
  * Local / tests:   DATABASE_URL, a full SQLAlchemy URL for a throwaway local
                     Postgres (or SQLite in the test suite).

Two places uploaded PDFs can go (STORAGE_BACKEND):

  * "gcs"    Google Cloud Storage bucket GCS_BUCKET, accessed with the VM's
             service account through the metadata server - no key files.
  * "local"  UPLOAD_DIRECTORY on local disk (laptop development and tests).
"""
from typing import Literal, Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # env_file is deliberately NOT set: configuration comes from the process
    # environment only, so a stray .env can never be picked up in the cloud.
    model_config = SettingsConfigDict(extra="ignore")

    # --- Google Cloud ---------------------------------------------------------
    GCP_PROJECT: Optional[str] = None  # defaults to the project of the VM's identity

    # --- Database: cloud (Cloud SQL on a private IP) -------------------------
    CLOUDSQL_INSTANCE: Optional[str] = None   # e.g. "gridpulse-db"
    DB_HOST: Optional[str] = None             # overrides the private-IP lookup
    DB_PORT: int = 5432
    DB_NAME: str = "gridpulse"
    DB_USER: str = "gridpulse"
    DB_PASSWORD_SECRET: Optional[str] = None  # secret NAME in Secret Manager, never the value
    DB_SSLMODE: str = "require"               # Cloud SQL is created with ENCRYPTED_ONLY

    # --- Database: local development / tests ---------------------------------
    DATABASE_URL: Optional[str] = None

    # --- File storage ---------------------------------------------------------
    STORAGE_BACKEND: Literal["local", "gcs"] = "local"
    GCS_BUCKET: Optional[str] = None
    GCS_PREFIX: str = "documents"
    UPLOAD_DIRECTORY: str = "./uploads"

    MODEL_PATH: str = "./ml/model.joblib"

    CORS_ORIGINS: str = "http://localhost:5173,http://127.0.0.1:5173"

    # Risk thresholds - ratio of predicted_load_mw / effective_capacity_mw
    RISK_WATCH_PCT: float = 0.75
    RISK_HIGH_PCT: float = 0.85
    RISK_CRITICAL_PCT: float = 0.95

    FORECAST_HORIZON_HOURS: int = 24
    MAX_UPLOAD_MB: int = 10

    # A job left in "processing" longer than this (e.g. the VM died mid-job)
    # is put back in the queue when the worker starts.
    STALE_JOB_MINUTES: int = 10

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @property
    def uses_cloud_database(self) -> bool:
        return not self.DATABASE_URL and bool(self.DB_PASSWORD_SECRET)


settings = Settings()
