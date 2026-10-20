"""
SQLAlchemy engine / session setup.

The connection URL is assembled at start-up (see app.config):
  * cloud: user + password from Secret Manager + Cloud SQL private IP + TLS
  * local: DATABASE_URL as given
The password only ever lives in this process's memory. SQLAlchemy masks it as
*** whenever the URL is printed or logged.

Milestone 5: the backend runs as several replicas on GKE, each with its own
connection pool, so the pools are deliberately small (see app.config) and the
readiness probe gets a dedicated one-connection pool. That way a busy pod can
still answer "is the database reachable?" instantly instead of queueing behind
real requests and being wrongly marked not-ready under load.
"""
from sqlalchemy import create_engine, text
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

    host = settings.DB_HOST or gcp.with_retries(
        gcp.cloudsql_private_ip, settings.CLOUDSQL_INSTANCE, what="Cloud SQL private-IP lookup"
    )
    password = gcp.with_retries(
        gcp.access_secret, settings.DB_PASSWORD_SECRET, what="Secret Manager read"
    )
    return URL.create(
        "postgresql+psycopg2",
        username=settings.DB_USER,
        password=password,
        host=host,
        port=settings.DB_PORT,
        database=settings.DB_NAME,
        query={
            "sslmode": settings.DB_SSLMODE,
            "connect_timeout": str(settings.DB_CONNECT_TIMEOUT),
        },
    )


def _pool_options(url: URL, *, size: int, overflow: int, timeout: int) -> dict:
    if url.get_backend_name() == "sqlite":
        return {}  # test suite: SQLAlchemy's default SQLite pool
    return {
        "pool_size": size,
        "max_overflow": overflow,
        "pool_timeout": timeout,
        "pool_recycle": 1800,  # Cloud SQL closes idle connections eventually
    }


DATABASE_URL = build_database_url()

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    **_pool_options(
        DATABASE_URL,
        size=settings.DB_POOL_SIZE,
        overflow=settings.DB_MAX_OVERFLOW,
        timeout=settings.DB_POOL_TIMEOUT,
    ),
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# One connection, used only by the readiness probe (GET /api/health/ready).
health_engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    **_pool_options(DATABASE_URL, size=1, overflow=0, timeout=2),
)

Base = declarative_base()


def get_db():
    """FastAPI dependency: yields a DB session and always closes it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def check_database() -> None:
    """Raise if the database cannot answer SELECT 1 (readiness probe)."""
    with health_engine.connect() as connection:
        connection.execute(text("SELECT 1"))
