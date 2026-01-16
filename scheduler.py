import logging
import sys
from datetime import datetime
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger
import os

# Configure logging
# 自定义 Handler 实现每条日志必刷新
class RealTimeFileHandler(logging.FileHandler):
    def emit(self, record):
        super().emit(record)
        self.flush() # 强制刷新到磁盘
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [%(levelname)s] - [%(name)s] - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        RealTimeFileHandler("scheduler.log", encoding='utf-8')
    ],
    force=True # 强制覆盖之前的配置
)
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
        
def start_scheduler():
    cycle_job()  # 先运行一次

    scheduler = BlockingScheduler()
    
    scheduler.add_job(
        cycle_job,
        trigger=CronTrigger(minute=0),
        id='run_all_cycle',
        name='Fetch articles and process LLM summaries every hour',
        replace_existing=True
    )


    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        logger.info("Scheduler stopped.")

if __name__ == "__main__":
    start_scheduler()
