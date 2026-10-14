"""The Alembic migration (not the app) creates the tables. Check it contains a
real CREATE TABLE for every ORM table and every column, so the two can't drift."""
import re
from pathlib import Path

from app.database import Base
from app import models  # noqa: F401

MIGRATION = Path(__file__).resolve().parent.parent / "migrations" / "versions" / "0001_initial_schema.py"


def _create_blocks():
    sql = MIGRATION.read_text()
    return {
        m.group(1): m.group(2)
        for m in re.finditer(r"CREATE TABLE (\w+) \((.*?)\n\s*\)\n", sql, re.S)
    }


def test_migration_creates_every_table_and_column():
    blocks = _create_blocks()
    assert set(blocks) == set(Base.metadata.tables), "migration and ORM table lists differ"
    for name, table in Base.metadata.tables.items():
        for column in table.columns:
            assert re.search(rf"^\s*{column.name}\s", blocks[name], re.M), f"{name}.{column.name} missing"


def test_migration_has_indexes():
    sql = MIGRATION.read_text()
    for table in Base.metadata.tables.values():
        for index in table.indexes:
            assert f"CREATE INDEX {index.name}" in sql
