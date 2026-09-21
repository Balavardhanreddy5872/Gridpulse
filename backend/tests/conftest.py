"""
Test fixtures. Uses a throwaway SQLite file for the whole test session
instead of Postgres so `pytest` works with zero setup - the app's
SQLAlchemy layer doesn't use any Postgres-specific features, so this is a
faithful enough substitute for schema/endpoint tests. Env vars must be
set BEFORE importing anything under app/, since app.config.Settings
reads them at import time.

Tables are created once per session, then wiped before every individual
test (not after) so each test starts from a known-empty state regardless
of what ran before it or in what order - this matters here because
several tests deliberately check "zero rows" behavior (e.g. no regions
yet), which would flake if an earlier test's rows were still present.
"""
import os
import sys
from pathlib import Path

TEST_DB_PATH = Path(__file__).resolve().parent / "test_gridpulse.db"
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH}"
os.environ["UPLOAD_DIRECTORY"] = str(Path(__file__).resolve().parent / "test_uploads")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _init_db():
    if TEST_DB_PATH.exists():
        TEST_DB_PATH.unlink()
    from app.database import Base, engine
    Base.metadata.create_all(bind=engine)
    yield
    if TEST_DB_PATH.exists():
        TEST_DB_PATH.unlink()


@pytest.fixture(autouse=True)
def _clean_tables():
    from app.database import SessionLocal, Base
    session = SessionLocal()
    try:
        for table in reversed(Base.metadata.sorted_tables):
            session.execute(table.delete())
        session.commit()
    finally:
        session.close()
    yield


@pytest.fixture()
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def db_session():
    from app.database import SessionLocal
    session = SessionLocal()
    yield session
    session.close()


@pytest.fixture()
def sample_region(db_session):
    from app.models import Region
    region = Region(name="Test Region", state="TX", capacity_mw=1000)
    db_session.add(region)
    db_session.commit()
    db_session.refresh(region)
    return region
