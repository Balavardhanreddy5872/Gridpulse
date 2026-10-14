"""
SQLAlchemy engine / session setup.

The connection URL is assembled at start-up (see app.config):
  * cloud: user + password from Secret Manager + Cloud SQL private IP + TLS
  * local: DATABASE_URL as given
The password only ever lives in this process's memory. SQLAlchemy masks it as
*** whenever the URL is printed or logged.
"""
from sqlalchemy import create_engine
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import declarative_base, sessionmaker

from app.config import settings


def build_database_url() -> URL:
    if settings.DATABASE_URL:
        return make_url(settings.DATABASE_URL)

    if not settings.DB_PASSWORD_SECRET:
        raise RuntimeError(
            "No database configured. Cloud: set DB_PASSWORD_SECRET plus CLOUDSQL_INSTANCE "
            "(or DB_HOST). Local: set DATABASE_URL."
        )
    if not (settings.DB_HOST or settings.CLOUDSQL_INSTANCE):
        raise RuntimeError("Set CLOUDSQL_INSTANCE (or DB_HOST) to reach Cloud SQL")

    from app import gcp

    host = settings.DB_HOST or gcp.cloudsql_private_ip(settings.CLOUDSQL_INSTANCE)
    return URL.create(
        "postgresql+psycopg2",
        username=settings.DB_USER,
        password=gcp.access_secret(settings.DB_PASSWORD_SECRET),
        host=host,
        port=settings.DB_PORT,
        database=settings.DB_NAME,
        query={"sslmode": settings.DB_SSLMODE},
    )


DATABASE_URL = build_database_url()

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """FastAPI dependency: yields a DB session and always closes it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
