"""
PaperPulse Backend — Unified Entry Point

Starts the background scheduler and the FastAPI server in a single process.
Intended for both local development (`python run.py`) and Docker containers.

Usage:
    python run.py                       # defaults: 0.0.0.0:8000
    python run.py --host 127.0.0.1 --port 9000
    python run.py --no-scheduler        # API only, skip scheduler
"""

import argparse
import logging
import os
import sys

import dotenv
import uvicorn


# ── Logging ──────────────────────────────────────────────────────────────────

LOG_FORMAT = "%(asctime)s - [%(levelname)s] - [%(name)s] - %(message)s"

logging.basicConfig(
    level=logging.INFO,
    format=LOG_FORMAT,
    handlers=[logging.StreamHandler(sys.stdout)],
    force=True,
)
logger = logging.getLogger("run")


# ── Environment ──────────────────────────────────────────────────────────────

def load_env():
    """Load .env file if present (no-op inside Docker where env is injected)."""
    env_file = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.isfile(env_file):
        dotenv.load_dotenv(env_file, override=False)
        logger.info("Loaded environment from .env")


# ── Pre-flight checks ───────────────────────────────────────────────────────

REQUIRED_ENV_VARS = [
    "DATABASE_URL",
    "REDIS_URL",
    "JWT_SECRET",
]

OPTIONAL_ENV_VARS = [
    "LLM_BASE_URL",
    "LM_API_KEY",
    "Elsevier_KEY",
    "SMTP_SERVER",
    "SMTP_PORT",
    "SMTP_USERNAME",
    "SMTP_KEY",
    "SOURCE_EMAIL",
    "CORS_ORIGINS",
]


def check_config():
    """Verify that all critical environment variables are set.

    Logs warnings for optional variables that are missing.
    Exits the process if any required variable is absent.
    """
    missing = [v for v in REQUIRED_ENV_VARS if not os.getenv(v)]
    if missing:
        logger.error("Missing REQUIRED environment variables: %s", ", ".join(missing))
        sys.exit(1)

    missing_optional = [v for v in OPTIONAL_ENV_VARS if not os.getenv(v)]
    if missing_optional:
        logger.warning(
            "Missing optional environment variables (some features may be disabled): %s",
            ", ".join(missing_optional),
        )

    logger.info("Configuration check passed.")


# ── Service probes ───────────────────────────────────────────────────────────

PROBE_TIMEOUT_SECS = 5


def check_db():
    """Probe the PostgreSQL database with a SELECT 1.

    Uses a short-lived throw-away engine with a connect_timeout so the
    process does not hang when the database is unreachable.
    Exits the process with a human-readable error on failure.
    """
    from sqlalchemy import create_engine, text
    from sqlalchemy.exc import OperationalError, ArgumentError

    db_url = os.getenv("DATABASE_URL", "")
    # Build a display-safe URL (mask password)
    display_url = db_url
    if "@" in db_url:
        pre, rest = db_url.split("@", 1)
        if ":" in pre:
            display_url = f"{pre.rsplit(':', 1)[0]}:***@{rest}"

    logger.info("Probing database (timeout=%ds): %s", PROBE_TIMEOUT_SECS, display_url)
    probe_engine = None
    try:
        probe_engine = create_engine(
            db_url,
            connect_args={"connect_timeout": PROBE_TIMEOUT_SECS},
            pool_size=1,
            max_overflow=0,
        )
        with probe_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        logger.info("Database connection OK.")
    except ArgumentError as e:
        logger.error(
            "DATABASE_URL is malformed — check the format:\n"
            "  Expected: postgresql+psycopg://user:password@host:port/dbname\n"
            "  Got     : %s\n"
            "  Detail  : %s",
            display_url, e,
        )
        sys.exit(1)
    except OperationalError as e:
        # Extract the most useful part of the psycopg error
        cause = str(e.orig) if e.orig else str(e)
        first_line = cause.splitlines()[0]
        if "timeout" in first_line.lower() or "timed out" in first_line.lower():
            logger.error(
                "Database probe timed out after %ds — is PostgreSQL reachable at %s?",
                PROBE_TIMEOUT_SECS, display_url,
            )
        else:
            logger.error(
                "Cannot connect to PostgreSQL at %s\n"
                "  %s\n"
                "  Make sure the database is running and credentials are correct.",
                display_url, first_line,
            )
        sys.exit(1)
    except Exception as e:
        logger.error("Database probe failed: %s", e)
        sys.exit(1)
    finally:
        if probe_engine is not None:
            probe_engine.dispose()


def check_redis():
    """Probe Redis connectivity and initialise the global Redis client.

    Exits the process if Redis is unreachable so problems surface at
    startup rather than at the first request.
    """
    from utils.redis_client import init_client

    redis_url = os.getenv("REDIS_URL", "")
    logger.info("Probing Redis: %s", redis_url)
    try:
        init_client()
        logger.info("Redis connection OK.")
    except RuntimeError as e:
        logger.error("Redis probe failed: %s", e)
        sys.exit(1)
    except Exception as e:
        logger.error("Unexpected error probing Redis: %s", e)
        sys.exit(1)


def init_db():
    """Run Alembic migrations to bring the database schema up to date.

    Safe to call on every startup — Alembic is idempotent and skips
    already-applied revisions.  If the database is brand-new (no tables
    yet) this creates the full schema; if it is already current it is a
    near-instant no-op.
    """
    import os
    from alembic.config import Config
    from alembic import command
    from alembic.util.exc import CommandError

    ini_path = os.path.join(os.path.dirname(__file__), "alembic.ini")
    if not os.path.isfile(ini_path):
        logger.error("alembic.ini not found at %s — cannot run migrations.", ini_path)
        sys.exit(1)

    logger.info("Running database migrations (alembic upgrade head)…")
    try:
        cfg = Config(ini_path)
        command.upgrade(cfg, "head")
        logger.info("Database schema is up to date.")
    except CommandError as e:
        logger.error("Alembic migration failed: %s", e)
        sys.exit(1)
    except Exception as e:
        logger.error("Unexpected error during database migration: %s", e)
        sys.exit(1)


# ── Banner ───────────────────────────────────────────────────────────────────

def print_banner(host: str, port: int, scheduler_enabled: bool):
    db_url = os.getenv("DATABASE_URL", "")
    # Mask password in URL for display
    display_db = db_url
    if "@" in db_url:
        pre, rest = db_url.split("@", 1)
        if ":" in pre:
            scheme_user = pre.rsplit(":", 1)[0]
            display_db = f"{scheme_user}:***@{rest}"

    redis_url = os.getenv("REDIS_URL", "")

    art = [
        "  _____                      _____       _",
        " |  __ \\                    |  __ \\     | |",
        " | |__) |_ _ _ __   ___ _ __| |__) |   _| |___  ___",
        " |  ___/ _` | '_ \\ / _ \\ '__|  ___/ | | | / __|/ _ \\",
        " | |  | (_| | |_) |  __/ |  | |   | |_| | \\__ \\  __/",
        " |_|   \\__,_| .__/ \\___|_|  |_|    \\__,_|_|___/\\___|",
        "            | |",
        "            |_|",
    ]

    lines = [
        "",
        "=" * 58,
    ] + art + [
        "=" * 58,
        f"  API Server : http://{host}:{port}",
        f"  Database   : {display_db}",
        f"  Redis      : {redis_url}",
        f"  Scheduler  : {'ON  (hourly cycle)' if scheduler_enabled else 'OFF (--no-scheduler)'}",
        "=" * 58,
        "",
    ]
    print("\n".join(lines), flush=True)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="PaperPulse Backend")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8000, help="Bind port (default: 8000)")
    parser.add_argument(
        "--no-scheduler",
        action="store_true",
        help="Start API server only, without background scheduler",
    )
    args = parser.parse_args()

    # 1. Load .env (local dev) — in Docker env is injected, this is a no-op
    load_env()

    # 2. Check required config
    check_config()

    # 3. Probe database connectivity
    check_db()

    # 4. Probe Redis connectivity & initialise client
    check_redis()

    # 5. Initialize / migrate schema
    init_db()

    # 6. Optionally start background scheduler
    bg_scheduler = None
    if not args.no_scheduler:
        from scheduler import start_background_scheduler

        bg_scheduler = start_background_scheduler()

    # 7. Show banner
    print_banner(args.host, args.port, scheduler_enabled=(bg_scheduler is not None))

    # 8. Run uvicorn (blocks until shutdown)
    try:
        uvicorn.run(
            "app.main:app",
            host=args.host,
            port=args.port,
            log_level="info",
            access_log=True,
        )
    finally:
        if bg_scheduler is not None:
            logger.info("Shutting down scheduler...")
            bg_scheduler.shutdown(wait=False)
            logger.info("Scheduler stopped.")
        logger.info("PaperPulse Backend exited.")


if __name__ == "__main__":
    main()
