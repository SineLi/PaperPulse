import logging
import os
import time
import asyncio
from dataclasses import dataclass
from typing import Any

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
from utils.task_executor import ArticleFetchTask, TaskExecutor

logger = logging.getLogger(__name__)
FETCHER_WARN_AFTER_SECS = 5 * 60
ARTICLE_FETCH_EXECUTOR_WORKERS = int(os.getenv("ARTICLE_FETCH_EXECUTOR_WORKERS", "8"))
ARTICLE_FETCH_EXECUTOR_TIMEOUT_SECS = float(os.getenv("ARTICLE_FETCH_EXECUTOR_TIMEOUT_SECS", "1800"))

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


@dataclass
class FetcherBatch:
    fetcher: Any
    papers: list[dict]
    journal_name: str
    publisher: str
    started_at: float
    tasks: list[ArticleFetchTask]

    @property
    def completed_papers(self) -> list[dict]:
        """返回已实际执行结束的文章，排除因整批超时而取消的任务。"""

        return [
            task.article
            for task in self.tasks
            if task.result is not None and not task.result.cancelled
        ]


async def run_enabled_fetchers_async(
    journal_timeout_secs: float = 1800,
    executor_timeout_secs: float | None = None,
):
    total_started_at = time.monotonic()
    browser_manager = BrowserManager()
    if executor_timeout_secs is None:
        executor_timeout_secs = ARTICLE_FETCH_EXECUTOR_TIMEOUT_SECS
    if journal_timeout_secs <= 0 or executor_timeout_secs <= 0:
        raise ValueError("fetcher timeouts must be positive")

    log_event(
        logger,
        logging.INFO,
        "fetchers_started",
        journal_timeout_secs=journal_timeout_secs,
        executor_timeout_secs=executor_timeout_secs,
    )
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

        fetcher_batches: list[FetcherBatch] = []
        article_tasks: list[ArticleFetchTask] = []

        # 第一阶段依次执行轻量的 RSS/列表收集和去重，不在各 fetcher 内启动详情页并发。
        # 所有期刊的新文章汇总后再入同一个队列，使 Playwright 并发上限对本轮调度全局生效。
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

                batch_tasks = [
                    ArticleFetchTask(
                        fetcher=fetcher,
                        papers_to_fetch=papers_to_fetch,
                        index=idx,
                    )
                    for idx in range(len(papers_to_fetch))
                ]
                fetcher_batches.append(
                    FetcherBatch(
                        fetcher=fetcher,
                        papers=papers_to_fetch,
                        journal_name=j_name,
                        publisher=j_publisher,
                        started_at=journal_started_at,
                        tasks=batch_tasks,
                    )
                )
                article_tasks.extend(batch_tasks)

                log_event(
                    logger,
                    logging.INFO,
                    "journal_fetch_queued",
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
                    "journal_collect_completed",
                    journal=j_name,
                    publisher=j_publisher,
                    elapsed_secs=elapsed,
                )

        if article_tasks:
            log_event(logger, logging.INFO, "fetchers_browser_pool_init_started")
            try:
                await browser_manager.init_browser_pool()
            except Exception as exc:
                logger.exception("event=fetchers_browser_pool_init_failed detail=%s", exc)
                return
            log_event(logger, logging.INFO, "fetchers_browser_pool_init_completed")

            # 单个期刊原有的 max_workers 不参与此路径；真正的详情抓取并发由这里统一控制。
            executor = TaskExecutor(max_workers=ARTICLE_FETCH_EXECUTOR_WORKERS)
            try:
                executor_stats = await asyncio.wait_for(
                    executor.run(article_tasks),
                    timeout=executor_timeout_secs,
                )
                log_event(logger, logging.INFO, "article_fetch_executor_completed", **executor_stats)
            except asyncio.TimeoutError:
                cancelled_count = sum(
                    1
                    for task in article_tasks
                    if task.result is not None and task.result.cancelled
                )
                log_event(
                    logger,
                    logging.WARNING,
                    "article_fetch_executor_timeout",
                    timeout_secs=executor_timeout_secs,
                    queued=len(article_tasks),
                    cancelled=cancelled_count,
                )
            except Exception as exc:
                logger.exception("event=article_fetch_executor_failed detail=%s", exc)

        # ArticleFetchTask 持有原批次引用，队列已原地补全详情和抓取状态；
        # 第二阶段仍按期刊调用 finalize()，但整批超时后不处理尚未完成的任务。
        for batch in fetcher_batches:
            papers_to_record = batch.completed_papers
            if not papers_to_record:
                log_event(
                    logger,
                    logging.WARNING,
                    "journal_finalize_skipped_no_completed_tasks",
                    journal=batch.journal_name,
                    publisher=batch.publisher,
                    queued=len(batch.tasks),
                )
                continue

            try:
                await asyncio.wait_for(batch.fetcher.finalize(papers_to_record), timeout=journal_timeout_secs)
                elapsed = time.monotonic() - batch.started_at
                log_level = logging.WARNING if elapsed >= FETCHER_WARN_AFTER_SECS else logging.INFO
                log_event(
                    logger,
                    log_level,
                    "journal_fetch_completed",
                    journal=batch.journal_name,
                    publisher=batch.publisher,
                    article_count=len(papers_to_record),
                    cancelled_count=len(batch.tasks) - len(papers_to_record),
                    elapsed_secs=elapsed,
                )
            except asyncio.TimeoutError:
                log_event(
                    logger,
                    logging.WARNING,
                    "journal_finalize_timeout",
                    journal=batch.journal_name,
                    publisher=batch.publisher,
                    elapsed_secs=time.monotonic() - batch.started_at,
                )
            except Exception as e:
                logger.exception(
                    "event=journal_finalize_failed journal=%s publisher=%s detail=%s",
                    batch.journal_name,
                    batch.publisher,
                    e,
                )

        log_event(logger, logging.INFO, "fetchers_completed", elapsed_secs=time.monotonic() - total_started_at)
    finally:
        await browser_manager.close_all_browsers()


def run_enabled_fetchers(
    journal_timeout_secs: float = 1800,
    executor_timeout_secs: float | None = None,
):
    return asyncio.run(
        run_enabled_fetchers_async(
            journal_timeout_secs=journal_timeout_secs,
            executor_timeout_secs=executor_timeout_secs,
        )
    )


if __name__ == "__main__":
    asyncio.run(run_enabled_fetchers_async())
