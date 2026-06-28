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

from utils.browser_manager import BrowserManager

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


async def _run_fetcher(fetcher, papers_to_fetch):
    await fetcher._fetch_details_concurrently(papers_to_fetch)
    await fetcher.finalize(papers_to_fetch)


async def run_enabled_fetchers_async(journal_timeout_secs=1800):
    total_started_at = time.monotonic()
    browser_manager = BrowserManager()

    log_event(logger, logging.INFO, "fetchers_started", journal_timeout_secs=journal_timeout_secs)
    try:
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

        log_event(logger, logging.INFO, "fetchers_loaded", journal_count=len(active_journals))

        if not active_journals:
            return

        log_event(logger, logging.INFO, "fetchers_browser_pool_init_started")
        try:
            await browser_manager.init_browser_pool()
        except Exception as e:
            logger.exception("Error initializing browser pool: %s", e)
            return
        log_event(logger, logging.INFO, "fetchers_browser_pool_init_completed")

        for journal in active_journals:
            journal_started_at = time.monotonic()
            journal = dict(journal)
            j_id = journal["id"]
            j_name = journal["name"]
            j_publisher = journal["publisher"]
            j_url = journal["rss_url"] if journal["rss_url"] else journal["official_url"]

            log_event(
                logger,
                logging.INFO,
                "journal_fetch_started",
                journal=j_name,
                journal_id=j_id,
                publisher=j_publisher,
            )
            try:
                if not j_url:
                    logger.warning(f"No URL found for {j_name}. Skipping.")
                    log_event(
                        logger,
                        logging.INFO,
                        "journal_fetch_completed",
                        journal=j_name,
                        journal_id=j_id,
                        skipped=True,
                    )
                    continue

                fetcher_cls = PUBLISHER_FETCHER_MAP.get(j_publisher)
                if fetcher_cls is None:
                    logger.warning(f"No fetcher for publisher {j_publisher} ({j_name}). Skipping.")
                    log_event(
                        logger,
                        logging.INFO,
                        "journal_fetch_completed",
                        journal=j_name,
                        journal_id=j_id,
                        skipped=True,
                    )
                    continue

                fetcher = fetcher_cls(
                    url=j_url,
                    name=j_name,
                    journal_id=j_id,
                    browser_manager=browser_manager,
                    max_workers=5,
                )

                papers_to_fetch = await asyncio.wait_for(fetcher.collect(), timeout=journal_timeout_secs)
                if not papers_to_fetch:
                    log_event(
                        logger,
                        logging.INFO,
                        "journal_fetch_completed",
                        journal=j_name,
                        journal_id=j_id,
                        article_count=0,
                    )
                    continue

                await asyncio.wait_for(
                    _run_fetcher(fetcher, papers_to_fetch),
                    timeout=journal_timeout_secs,
                )

                log_event(
                    logger,
                    logging.INFO,
                    "journal_fetch_completed",
                    journal=j_name,
                    journal_id=j_id,
                    article_count=len(papers_to_fetch),
                )
            except asyncio.TimeoutError:
                log_event(
                    logger,
                    logging.WARNING,
                    "journal_fetcher_timeout",
                    journal=j_name,
                    journal_id=j_id,
                    publisher=j_publisher,
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
                log_event(
                    logger,
                    log_level,
                    "journal_processing_completed",
                    journal=j_name,
                    publisher=j_publisher,
                    elapsed_secs=elapsed,
                )

        log_event(logger, logging.INFO, "fetchers_completed", elapsed_secs=time.monotonic() - total_started_at)
    finally:
        await browser_manager.close_all_browsers()


def run_enabled_fetchers(journal_timeout_secs=1800):
    return asyncio.run(run_enabled_fetchers_async(journal_timeout_secs=journal_timeout_secs))


if __name__ == "__main__":
    asyncio.run(run_enabled_fetchers_async())
