import logging
import time
import asyncio
from db.database import get_db_connection
from sqlalchemy import text
from utils.logging_utils import log_event

from utils.fetcher.AAAS_fetcher import ScienceFetcher
from utils.fetcher.ACS_fetcher import ACSFetcher
from utils.fetcher.Cell_fetcher import CellFetcher
from utils.fetcher.Elsevier_fetcher import ElsevierFetcher
from utils.fetcher.Frontiers_fetcher import FrontiersFetcher
from utils.fetcher.MDPI_fetcher import MDPIFetcher
from utils.fetcher.Nat_fetcher import NatureFetcher
from utils.fetcher.RSC_fetcher import RSCFetcher
from utils.fetcher.Taylor_fetcher import TaylorFetcher
from utils.fetcher.Wiely_fetcher import WileyFetcher

# 日志配置
logger = logging.getLogger(__name__)
FETCHER_WARN_AFTER_SECS = 5 * 60

# 出版商与抓取器类的映射关系
PUBLISHER_FETCHER_MAP = {
    "Springer Nature": NatureFetcher,
    "Cell Press": CellFetcher,
    "Elsevier": ElsevierFetcher,
    "Science": ScienceFetcher,
    "AAAS": ScienceFetcher,
    "American Chemical Society": ACSFetcher,
    "Royal Society of Chemistry": RSCFetcher,
    "Wiley": WileyFetcher,
    "Taylor & Francis": TaylorFetcher,
    "MDPI": MDPIFetcher,
    "Frontiers": FrontiersFetcher
}

async def run_enabled_fetchers_async(journal_timeout_secs=1800):
    total_started_at = time.monotonic()
    log_event(logger, logging.INFO, "fetchers_started")
    
    with get_db_connection() as conn:
        active_journals = conn.execute(
            text(
                """
                SELECT id, name, publisher, rss_url, official_url
                FROM journals
                WHERE crawler_enabled = TRUE
                """
            )
        ).mappings().all()

    if not active_journals:
        log_event(logger, logging.INFO, "fetchers_no_active_journals")
        return

    log_event(logger, logging.INFO, "fetchers_loaded", journal_count=len(active_journals))

    for journal in active_journals:
        journal = dict(journal)
        # 使用字典访问（因为使用了 Row factory）
        j_id = journal['id']
        j_name = journal['name']
        j_publisher = journal['publisher']
        # 优先使用 RSS URL，备选官网 URL
        j_url = journal['rss_url'] if journal['rss_url'] else journal['official_url']

        if not j_url:
            log_event(logger, logging.WARNING, "journal_skipped_missing_url", journal=j_name, publisher=j_publisher)
            continue

        log_event(logger, logging.INFO, "journal_processing_started", journal=j_name, publisher=j_publisher)

        # 查找匹配的抓取器类
        fetcher_class = PUBLISHER_FETCHER_MAP.get(j_publisher)

        if not fetcher_class:
            log_event(logger, logging.WARNING, "journal_skipped_missing_fetcher", journal=j_name, publisher=j_publisher)
            continue

        journal_started_at = time.monotonic()
        try:
            # 实例化抓取器 (已将所有 fetcher 更新为支持 url 和 name 参数)
            fetcher = fetcher_class(url=j_url, name=j_name, max_workers=5, journal_id=j_id)
            
            log_event(
                logger,
                logging.INFO,
                "journal_fetcher_started",
                journal=j_name,
                publisher=j_publisher,
                fetcher=fetcher.__class__.__name__,
                url=j_url,
            )

            try:
                await asyncio.wait_for(fetcher.run(), timeout=journal_timeout_secs)
            except asyncio.TimeoutError:
                log_event(
                    logger,
                    logging.WARNING,
                    "journal_fetcher_timeout",
                    journal=j_name,
                    publisher=j_publisher,
                    fetcher=fetcher.__class__.__name__,
                    url=j_url,
                    elapsed_secs=time.monotonic() - journal_started_at,
                )
            
        except Exception as e:
            logger.exception(
                "event=journal_fetcher_failed journal=%s publisher=%s detail=%s",
                j_name,
                j_publisher,
                e,
            )
        finally:
            elapsed = time.monotonic() - journal_started_at
            log_level = logging.WARNING if elapsed >= FETCHER_WARN_AFTER_SECS else logging.INFO
            log_event(logger, log_level, "journal_processing_completed", journal=j_name, publisher=j_publisher, elapsed_secs=elapsed)

    total_elapsed = time.monotonic() - total_started_at
    log_event(logger, logging.INFO, "fetchers_completed", elapsed_secs=total_elapsed)


def run_enabled_fetchers(journal_timeout_secs=1800):
    asyncio.run(run_enabled_fetchers_async(journal_timeout_secs=journal_timeout_secs))


if __name__ == "__main__":
    run_enabled_fetchers()

    def run_all_fetchers(self):
        for fetcher in self.fetchers:
            logger.info(f"Running fetcher: {fetcher.__class__.__name__}")
            new_articles = fetcher.fetch_new_articles()
            logger.info(f"Fetched {len(new_articles)} new articles from {fetcher.__class__.__name__}")
            for article in new_articles:
                self.article_repo.insert_article(article)
        logger.info("All fetchers completed.")
