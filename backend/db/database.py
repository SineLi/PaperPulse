import logging
import os
from contextlib import contextmanager
from typing import Iterator

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, Connection

logger = logging.getLogger(__name__)

_ENGINE: Engine | None = None


def _positive_int_env(name: str, default: int) -> int:
    raw_value = os.getenv(name, str(default))
    try:
        value = int(raw_value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be a positive integer") from exc
    if value <= 0:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


def get_engine() -> Engine:
    global _ENGINE
    if _ENGINE is not None:
        return _ENGINE

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise RuntimeError("DATABASE_URL is not set (expected postgresql+psycopg://...)")

    connect_timeout_secs = _positive_int_env("DB_CONNECT_TIMEOUT_SECS", 10)
    pool_timeout_secs = _positive_int_env("DB_POOL_TIMEOUT_SECS", 10)
    statement_timeout_ms = _positive_int_env("DB_STATEMENT_TIMEOUT_MS", 60_000)
    lock_timeout_ms = _positive_int_env("DB_LOCK_TIMEOUT_MS", 10_000)

    # 协程无法终止已进入同步数据库驱动的线程，因此必须由连接和 PostgreSQL 侧限制执行时间。
    _ENGINE = create_engine(
        db_url,
        pool_pre_ping=True,
        pool_timeout=pool_timeout_secs,
        connect_args={
            "connect_timeout": connect_timeout_secs,
            "options": (
                f"-c statement_timeout={statement_timeout_ms} "
                f"-c lock_timeout={lock_timeout_ms}"
            ),
        },
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
