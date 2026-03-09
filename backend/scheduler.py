import logging
import sys
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

logger = logging.getLogger(__name__)


try:
    from utils.main_fetcher import run_enabled_fetchers
    from services.LLM_service import LLMService
except ImportError as e:
    logger.error(f"Failed to import modules: {e}")
    sys.exit(1)

def cycle_job():
    service = LLMService()
    logger.info("Checking LLM task status...")
    try:
        service.run_update_cycle()
    except Exception as e:
        logger.error(f"LLM update cycle failed: {e}", exc_info=True)

    logger.info("Start fetching articles...")
    try:
        run_enabled_fetchers()
        logger.info("Finished fetching articles.")
    except Exception as e:
        logger.error(f"Article fetch scheduler failed: {e}", exc_info=True)

    try:
        service.run_submission_cycle()
    except Exception as e:
        logger.error(f"LLM submission cycle failed: {e}", exc_info=True)


def _add_jobs(scheduler):
    """Register all scheduled jobs onto the given scheduler instance."""
    scheduler.add_job(
        cycle_job,
        trigger=CronTrigger(minute=0),
        id='run_all_cycle',
        name='Fetch articles and process LLM summaries every hour',
        replace_existing=True,
    )


def start_background_scheduler() -> BackgroundScheduler:
    """Start a non-blocking BackgroundScheduler (for embedding in run.py).

    Returns the running scheduler so the caller can shut it down later.
    """
    scheduler = BackgroundScheduler()
    _add_jobs(scheduler)
    scheduler.start()
    logger.info("Background scheduler started.")
    return scheduler


def start_blocking_scheduler():
    """Start as a standalone blocking process (original behaviour)."""
    # 自定义 Handler 实现每条日志必刷新
    class RealTimeFileHandler(logging.FileHandler):
        def emit(self, record):
            super().emit(record)
            self.flush()

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - [%(levelname)s] - [%(name)s] - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            RealTimeFileHandler("scheduler.log", encoding='utf-8'),
        ],
        force=True,
    )

    cycle_job()  # 先运行一次

    scheduler = BlockingScheduler()
    _add_jobs(scheduler)

    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        logger.info("Scheduler stopped.")


if __name__ == "__main__":
    start_blocking_scheduler()
