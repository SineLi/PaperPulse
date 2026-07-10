import logging
import asyncio
import json
import os
from typing import Optional, List, Union, TypedDict

from sqlalchemy import text
from db.database import get_db_connection
from services.image_service import ImageService
from utils.logging_utils import log_event
from utils.task_executor import ImageCacheTask, TaskExecutor


logger = logging.getLogger(__name__)
IMAGE_CACHE_EXECUTOR_WORKERS = int(os.getenv("IMAGE_CACHE_EXECUTOR_WORKERS", "2"))
IMAGE_CACHE_EXECUTOR_TIMEOUT_SECS = float(os.getenv("IMAGE_CACHE_EXECUTOR_TIMEOUT_SECS", "600"))


class Article(TypedDict):
    title: str
    link: str
    doi: Optional[str]
    date: Optional[str]
    journal: Optional[str]
    authors: list[str]
    editor_summary: Optional[str]
    structured_abstract: Optional[str]
    abstract: Optional[str]
    graphical_abstract: Optional[str]
    status: str


class ArticleService:
    def __init__(self):
        self.image_service = ImageService()

    def article_filter(self, articles: List[dict]) -> List[dict]:
        if not articles:
            log_event(logger, logging.INFO, "article_filter_skipped_empty_input")
            return []

        input_count = len(articles)

        titles = [a.get("title") for a in articles if a.get("title")]
        links = [a.get("link") for a in articles if a.get("link")]
        dois = [a.get("doi") for a in articles if a.get("doi")]

        existing_titles: set[str] = set()
        existing_links: set[str] = set()
        existing_dois: set[str] = set()

        with get_db_connection() as conn:
            if titles:
                existing_titles.update(
                    conn.execute(text("SELECT title FROM articles WHERE title = ANY(:v)"), {"v": titles}).scalars().all()
                )
                existing_titles.update(
                    conn.execute(text("SELECT title FROM non_article_entries WHERE title = ANY(:v)"), {"v": titles}).scalars().all()
                )

            if links:
                existing_links.update(
                    conn.execute(text("SELECT link FROM articles WHERE link = ANY(:v)"), {"v": links}).scalars().all()
                )
                existing_links.update(
                    conn.execute(text("SELECT link FROM non_article_entries WHERE link = ANY(:v)"), {"v": links}).scalars().all()
                )

            if dois:
                existing_dois.update(
                    conn.execute(text("SELECT doi FROM articles WHERE doi = ANY(:v)"), {"v": dois}).scalars().all()
                )
                existing_dois.update(
                    conn.execute(text("SELECT doi FROM non_article_entries WHERE doi = ANY(:v)"), {"v": dois}).scalars().all()
                )

        new_articles = []
        for article in articles:
            title = article.get("title")
            link = article.get("link")
            doi = article.get("doi")

            if (doi and doi in existing_dois) or (title and title in existing_titles) or (link and link in existing_links):
                continue
            new_articles.append(article)

        log_event(
            logger,
            logging.INFO,
            "article_filter_completed",
            input_count=input_count,
            output_count=len(new_articles),
            duplicate_title_count=len(existing_titles),
            duplicate_link_count=len(existing_links),
            duplicate_doi_count=len(existing_dois),
        )

        return new_articles

    def insert_articles(self, articles: Union[List[dict], str]):
        if not articles:
            log_event(logger, logging.INFO, "article_insert_skipped_empty_input")
            return

        if isinstance(articles, str):
            try:
                articles = json.loads(articles)
            except json.JSONDecodeError as e:
                logger.exception("event=article_insert_json_decode_failed detail=%s", e)
                return

        with get_db_connection() as conn:
            journal_names = list({a.get("journal") for a in articles if a.get("journal")})
            journal_map: dict[str, int] = {}

            if journal_names:
                rows = conn.execute(
                    text("SELECT name, id FROM journals WHERE name = ANY(:names)"),
                    {"names": journal_names},
                ).mappings().all()
                journal_map = {r["name"]: int(r["id"]) for r in rows}

            data_to_insert: list[dict] = []
            non_article_rows: list[dict] = []

            for a in articles:
                title = a.get("title")
                link = a.get("link")
                abstract = a.get("abstract")
                fetch_status = a.get("_fetch_status", "unknown")
                fetch_fail_reason = a.get("_fetch_fail_reason")
                journal_id = journal_map.get(a.get("journal") or "")

                if not title or not link:
                    continue

                if not abstract:
                    if fetch_status != "ok":
                        log_event(
                            logger,
                            logging.WARNING,
                            "non_article_classification_skipped_due_fetch_status",
                            title=title,
                            status=fetch_status,
                            reason=fetch_fail_reason,
                        )
                        continue

                    if journal_id is None:
                        log_event(logger, logging.WARNING, "non_article_skipped_missing_journal_id", title=title, link=link)
                        continue

                    non_article_rows.append(
                        {
                            "title": title,
                            "link": link,
                            "date": a.get("date"),
                            "journal_id": journal_id,
                            "doi": a.get("doi"),
                        }
                    )
                    continue

                authors_json = json.dumps(a.get("authors", []), ensure_ascii=False)

                data_to_insert.append(
                    {
                        "title": title,
                        "link": link,
                        "doi": a.get("doi"),
                        "date": a.get("date"),
                        "journal_id": journal_id,
                        "authors": authors_json,
                        "editor_summary": a.get("editor_summary"),
                        "structured_abstract": a.get("structured_abstract"),
                        "abstract": a.get("abstract"),
                        "graphical_abstract": a.get("graphical_abstract"),
                        "ga_cache_status": "pending" if a.get("graphical_abstract") else None,
                        "status": a.get("status", "pending"),
                    }
                )

            if data_to_insert:
                insert_result = conn.execute(
                    text(
                        """
                        INSERT INTO articles (
                          title, link, doi, date, journal_id, authors,
                          editor_summary, structured_abstract, abstract, graphical_abstract, ga_cache_status, status
                        )
                        VALUES (
                          :title, :link, :doi, :date, :journal_id, :authors,
                          :editor_summary, :structured_abstract, :abstract, :graphical_abstract, :ga_cache_status, :status
                        )
                        ON CONFLICT DO NOTHING
                        RETURNING id, graphical_abstract
                        """
                    ),
                    data_to_insert,
                )

                if insert_result.returns_rows:
                    inserted_rows = [dict(row) for row in insert_result.mappings().all()]
                else:
                    links = [row["link"] for row in data_to_insert]
                    inserted_rows = [
                        dict(row)
                        for row in conn.execute(
                            text(
                                """
                                SELECT id, graphical_abstract
                                FROM articles
                                WHERE link = ANY(:links)
                                """
                            ),
                            {"links": links},
                        ).mappings().all()
                    ]

                log_event(
                    logger,
                    logging.INFO,
                    "article_insert_articles_completed",
                    attempted=len(data_to_insert),
                    rowcount=len(inserted_rows),
                )

            if non_article_rows:
                non_article_result = conn.execute(
                    text(
                        """
                        INSERT INTO non_article_entries (title, link, date, journal_id, doi)
                        VALUES (:title, :link, :date, :journal_id, :doi)
                        ON CONFLICT DO NOTHING
                        """
                    ),
                    non_article_rows,
                )
                log_event(
                    logger,
                    logging.INFO,
                    "article_insert_non_articles_completed",
                    attempted=len(non_article_rows),
                    rowcount=non_article_result.rowcount,
                )

            log_event(
                logger,
                logging.INFO,
                "article_insert_completed",
                article_rows=len(data_to_insert),
                non_article_rows=len(non_article_rows),
            )

    def insert_non_article_entry(self, entry: dict):
        if not entry.get("title") or not entry.get("link") or entry.get("journal_id") is None:
            log_event(logger, logging.WARNING, "non_article_insert_skipped_invalid_input")
            return

        with get_db_connection() as conn:
            result = conn.execute(
                text(
                    """
                    INSERT INTO non_article_entries (title, link, date, journal_id, doi)
                    VALUES (:title, :link, :date, :journal_id, :doi)
                    ON CONFLICT DO NOTHING
                    """
                ),
                {
                    "title": entry.get("title"),
                    "link": entry.get("link"),
                    "date": entry.get("date"),
                    "journal_id": entry.get("journal_id"),
                    "doi": entry.get("doi"),
                },

            )
            log_event(
                logger,
                logging.INFO,
                "non_article_insert_completed",
                title=entry.get("title"),
                link=entry.get("link"),
                rowcount=result.rowcount,
            )

    async def cache_missing_article_images_async(
        self,
        limit: int = 100,
        scan_limit: int | None = None,
        executor_timeout_secs: float | None = None,
    ) -> dict:
        """限流缓存待处理图片，并在任务结束后统一更新数据库状态。"""

        if limit <= 0:
            result = {
                "scanned": 0,
                "attempted": 0,
                "cached": 0,
                "failed": 0,
                "cancelled": 0,
                "skipped": 0,
            }
            log_event(logger, logging.INFO, "article_image_backfill_skipped_invalid_limit", limit=limit)
            return result

        if executor_timeout_secs is None:
            executor_timeout_secs = IMAGE_CACHE_EXECUTOR_TIMEOUT_SECS
        if executor_timeout_secs <= 0:
            raise ValueError("executor_timeout_secs must be positive")

        effective_scan_limit = scan_limit if scan_limit is not None else max(limit * 10, limit)
        with get_db_connection() as conn:
            rows = conn.execute(
                text(
                    """
                    SELECT id, graphical_abstract, ga_cache_status
                    FROM articles
                    WHERE ga_cache_status IN ('pending', 'failed')
                    ORDER BY
                      CASE ga_cache_status
                        WHEN 'pending' THEN 0
                        WHEN 'failed' THEN 1
                        ELSE 2
                      END,
                      id ASC
                    LIMIT :limit
                    """
                ),
                {"limit": effective_scan_limit},
            ).mappings().all()

        scanned = len(rows)
        attempted = 0
        cached = 0
        failed = 0
        cancelled = 0
        skipped = 0
        status_updates: list[dict] = []
        image_tasks: list[ImageCacheTask] = []

        for row in rows:
            article_id = int(row["id"])
            image_url = row.get("graphical_abstract")
            if not image_url:
                skipped += 1
                continue

            if self.image_service.has_cached_image(article_id):
                cached += 1
                status_updates.append({"id": article_id, "ga_cache_status": "cached"})
                continue

            if attempted >= limit:
                break

            attempted += 1
            image_tasks.append(ImageCacheTask(article_id=article_id, url=image_url))

        if image_tasks:
            # 图片下载会在 TaskExecutor 内转入线程，固定 worker 数限制整批回填并发。
            executor = TaskExecutor(max_workers=IMAGE_CACHE_EXECUTOR_WORKERS, image_service=self.image_service)
            try:
                await asyncio.wait_for(
                    executor.run(image_tasks),
                    timeout=executor_timeout_secs,
                )
            except asyncio.TimeoutError:
                log_event(
                    logger,
                    logging.WARNING,
                    "article_image_backfill_timeout",
                    timeout_secs=executor_timeout_secs,
                    attempted=attempted,
                )

        for task in image_tasks:
            # 队列只记录执行结果；数据库状态仍由 service 在全部任务结束后统一更新。
            if task.result and task.result.success:
                cached += 1
                status_updates.append({"id": task.article_id, "ga_cache_status": "cached"})
            elif task.result is None or task.result.cancelled:
                # 超时取消不代表图片本身失败，保留 pending 供下一轮继续尝试。
                cancelled += 1
                status_updates.append({"id": task.article_id, "ga_cache_status": "pending"})
            else:
                failed += 1
                status_updates.append({"id": task.article_id, "ga_cache_status": "failed"})

        self._update_ga_cache_statuses(status_updates)

        result = {
            "scanned": scanned,
            "attempted": attempted,
            "cached": cached,
            "failed": failed,
            "cancelled": cancelled,
            "skipped": skipped,
        }
        log_event(logger, logging.INFO, "article_image_backfill_completed", **result)
        return result

    def cache_missing_article_images(
        self,
        limit: int = 100,
        scan_limit: int | None = None,
        executor_timeout_secs: float | None = None,
    ) -> dict:
        """为同步调用方保留的兼容入口；异步代码应调用对应 async 方法。"""

        try:
            asyncio.get_running_loop()
        except RuntimeError:
            pass
        else:
            raise RuntimeError("async callers must use cache_missing_article_images_async")

        return asyncio.run(
            self.cache_missing_article_images_async(
                limit=limit,
                scan_limit=scan_limit,
                executor_timeout_secs=executor_timeout_secs,
            )
        )

    def _update_ga_cache_statuses(self, updates: list[dict], conn=None) -> None:
        if not updates:
            return

        query = text(
            """
            UPDATE articles
            SET ga_cache_status = :ga_cache_status
            WHERE id = :id
            """
        )

        if conn is not None:
            conn.execute(query, updates)
            return

        with get_db_connection() as update_conn:
            update_conn.execute(query, updates)
