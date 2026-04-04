import logging
import sys
import time
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

from utils.logging_utils import configure_logging, log_event

logger = logging.getLogger(__name__)
STEP_WARN_AFTER_SECS = 5 * 60
CYCLE_WARN_AFTER_SECS = 50 * 60


try:
    from utils.main_fetcher import run_enabled_fetchers
    from services.article_services import ArticleService
    from services.LLM_service import LLMService
except ImportError as e:
    log_event(logger, logging.ERROR, "scheduler_import_failed", detail=e)
    sys.exit(1)


def _log_step_duration(step_name: str, started_at: float):
    elapsed = time.monotonic() - started_at
    log_level = logging.WARNING if elapsed >= STEP_WARN_AFTER_SECS else logging.INFO
    log_event(logger, log_level, "scheduler_step_completed", step=step_name, elapsed_secs=elapsed)


def cycle_job():
    cycle_started_at = time.monotonic()
    service = LLMService()
    log_event(logger, logging.INFO, "scheduler_cycle_started")

    step_started_at = time.monotonic()
    log_event(logger, logging.INFO, "scheduler_step_started", step="llm_update")
    try:
        service.run_update_cycle()
    except Exception as e:
        logger.exception("event=scheduler_step_failed step=llm_update detail=%s", e)
    finally:
        _log_step_duration("LLM update cycle", step_started_at)

    step_started_at = time.monotonic()
    log_event(logger, logging.INFO, "scheduler_step_started", step="article_fetch")
    try:
        run_enabled_fetchers()
        log_event(logger, logging.INFO, "scheduler_step_succeeded", step="article_fetch")
    except Exception as e:
        logger.exception("event=scheduler_step_failed step=article_fetch detail=%s", e)
    finally:
        _log_step_duration("Article fetch cycle", step_started_at)

    step_started_at = time.monotonic()
    log_event(logger, logging.INFO, "scheduler_step_started", step="llm_submission")
    try:
        service.run_submission_cycle()
    except Exception as e:

        logger.exception("event=scheduler_step_failed step=llm_submission detail=%s", e)
    finally:
        _log_step_duration("LLM submission cycle", step_started_at)

    cycle_elapsed = time.monotonic() - cycle_started_at
    log_level = logging.WARNING if cycle_elapsed >= CYCLE_WARN_AFTER_SECS else logging.INFO
    log_event(logger, log_level, "scheduler_cycle_completed", elapsed_secs=cycle_elapsed)


def image_cache_backfill_job(limit: int = 100, scan_limit: int = 1000):
    started_at = time.monotonic()
    service = ArticleService()
    log_event(
        logger,
        logging.INFO,
        "scheduler_step_started",
        step="image_cache_backfill",
        limit=limit,
        scan_limit=scan_limit,
    )
    try:
        result = service.cache_missing_article_images(limit=limit, scan_limit=scan_limit)
        log_event(logger, logging.INFO, "scheduler_step_succeeded", step="image_cache_backfill", **result)
    except Exception as e:
        logger.exception("event=scheduler_step_failed step=image_cache_backfill detail=%s", e)
    finally:
        _log_step_duration("Image cache backfill", started_at)



def _add_jobs(scheduler):
    """Register all scheduled jobs onto the given scheduler instance."""
    scheduler.add_job(
        cycle_job,
        trigger=CronTrigger(minute=0),
        id='run_all_cycle',
        name='Fetch articles and process LLM summaries every hour',
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        image_cache_backfill_job,
        trigger=CronTrigger(minute="*/15"),
        id="image_cache_backfill",
        name="Backfill missing cached images every 15 minutes",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )


def start_background_scheduler() -> BackgroundScheduler:
    """Start a non-blocking BackgroundScheduler (for embedding in run.py).

    Returns the running scheduler so the caller can shut it down later.
    """
    scheduler = BackgroundScheduler()
    _add_jobs(scheduler)
    scheduler.start()
    # Schedule one immediate run in the background thread so it does NOT
    # block the main thread (uvicorn startup).
    scheduler.add_job(cycle_job, id='initial_cycle', name='Initial cycle on startup')
    logger.info("Background scheduler started.")
    scheduler.add_job(
        image_cache_backfill_job,
        id="initial_image_cache_backfill",
        name="Initial image cache backfill on startup",
    )

    return scheduler


def start_blocking_scheduler():
    """Start as a standalone blocking process (original behaviour)."""
    # 自定义 Handler 实现每条日志必刷新
    configure_logging(logfile="scheduler.log", force=True)

    cycle_job()  # 先运行一次

    image_cache_backfill_job()

    scheduler = BlockingScheduler()
    _add_jobs(scheduler)

    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        log_event(logger, logging.INFO, "scheduler_stopped", mode="blocking")


if __name__ == "__main__":
    start_blocking_scheduler()
