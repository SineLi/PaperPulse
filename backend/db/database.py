import logging
import os
from contextlib import contextmanager
from typing import Iterator

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, Connection

logger = logging.getLogger(__name__)

_ENGINE: Engine | None = None


def get_engine() -> Engine:
    global _ENGINE
    if _ENGINE is not None:
        return _ENGINE

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise RuntimeError("DATABASE_URL is not set (expected postgresql+psycopg://...)")

    _ENGINE = create_engine(
        db_url,
        pool_pre_ping=True,
        future=True,
    )
    return _ENGINE


def init_database(*args, **kwargs):
    raise RuntimeError("init_database is deprecated. Use Alembic migrations for Postgres.")


@contextmanager
def get_db_connection() -> Iterator[Connection]:
    engine = get_engine()
    with engine.begin() as conn:
        yield conn