import asyncio
import threading
import unittest
from contextlib import contextmanager
from datetime import datetime, timezone
from unittest.mock import patch

from sqlalchemy import create_engine, text
from services import article_services


class FakeImages:
    def __init__(self):
        self.started = threading.Event()
        self.release = threading.Event()
        self.release.set()
        self.calls = []
        self.success = False
        self.cached_ids = set()

    def has_cached_image(self, article_id):
        return article_id in self.cached_ids

    def cache_image(self, url, article_id):
        self.calls.append(article_id)
        self.started.set()
        self.release.wait(timeout=2)
        if self.success:
            return {"path": str(article_id) + ".webp", "status": "cached"}
        return {"path": None, "status": "failed", "error": "blocked"}


class ArticleBackfillTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://")
        self.addCleanup(self.engine.dispose)
        with self.engine.begin() as conn:
            conn.execute(text("""
                CREATE TABLE articles (
                    id INTEGER PRIMARY KEY, graphical_abstract TEXT,
                    ga_cache_status TEXT, ga_cache_attempts INTEGER DEFAULT 0,
                    ga_cache_next_retry_at TIMESTAMP
                )
            """))
        self.service = article_services.ArticleService.__new__(article_services.ArticleService)
        self.images = FakeImages()
        self.service.image_service = self.images
        self.db_patch = patch.object(article_services, "get_db_connection", self.connection)
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)
        self.worker_patch = patch.object(article_services, "IMAGE_CACHE_EXECUTOR_WORKERS", 1)
        self.worker_patch.start()
        self.addCleanup(self.worker_patch.stop)

    @contextmanager
    def connection(self):
        with self.engine.begin() as conn:
            yield conn

    def add_image(self, article_id, status="pending", attempts=0):
        with self.connection() as conn:
            conn.execute(text("""
                INSERT INTO articles (id, graphical_abstract, ga_cache_status, ga_cache_attempts)
                VALUES (:id, :url, :status, :attempts)
            """), {"id": article_id, "url": "https://example.com/image.png", "status": status, "attempts": attempts})

    def image(self, article_id):
        with self.connection() as conn:
            return dict(conn.execute(text("SELECT * FROM articles WHERE id = :id"), {"id": article_id}).mappings().one())

    async def test_timeout_stops_queue_and_records_running_thread_result(self):
        self.add_image(1)
        self.add_image(2)
        self.add_image(3, "failed", attempts=5)
        self.images.success = True
        self.images.release.clear()
        task = asyncio.create_task(self.service.cache_missing_article_images_async(limit=3, executor_timeout_secs=0.02))
        try:
            self.assertTrue(await asyncio.to_thread(self.images.started.wait, 1))
            await asyncio.sleep(0.05)
            self.assertFalse(task.done(), "必须等已启动的下载线程结束")
            self.assertEqual(self.images.calls, [1])
        finally:
            self.images.release.set()
            result = await asyncio.wait_for(task, timeout=1)
        self.assertEqual(result["cached"], 1)
        self.assertEqual(result["cancelled"], 2)
        self.assertEqual(self.images.calls, [1])
        self.assertEqual(self.image(1)["ga_cache_status"], "cached")
        self.assertEqual(self.image(2)["ga_cache_status"], "pending")
        self.assertEqual(self.image(3)["ga_cache_status"], "failed")
        self.assertEqual(self.image(3)["ga_cache_attempts"], 5)

    async def test_failed_images_cool_down_across_service_instances(self):
        self.add_image(1)
        self.add_image(2)
        first = await self.service.cache_missing_article_images_async(limit=2)
        self.assertEqual(first["failed"], 2)
        row = self.image(1)
        retry = datetime.fromisoformat(row["ga_cache_next_retry_at"])
        self.assertGreater((retry - datetime.now(timezone.utc)).total_seconds(), 3500)
        self.assertEqual(row["ga_cache_attempts"], 1)

        # 新 service 没有任何内存重试状态，仍由数据库阻止立刻重试。
        fresh_service = article_services.ArticleService.__new__(article_services.ArticleService)
        fresh_service.image_service = self.images
        second = await fresh_service.cache_missing_article_images_async(limit=2)
        self.assertEqual(second["attempted"], 0)
        self.assertEqual(self.images.calls, [1, 2])

        with self.connection() as conn:
            conn.execute(text("UPDATE articles SET ga_cache_next_retry_at = '2000-01-01' WHERE id = 1"))
        await fresh_service.cache_missing_article_images_async(limit=2)
        self.assertEqual(self.images.calls, [1, 2, 1])
        row = self.image(1)
        self.assertEqual(row["ga_cache_attempts"], 2)
        retry = datetime.fromisoformat(row["ga_cache_next_retry_at"])
        self.assertGreater((retry - datetime.now(timezone.utc)).total_seconds(), 7100)

    async def test_existing_cache_resets_retry_state_without_download(self):
        self.add_image(1, "failed", attempts=4)
        self.images.cached_ids.add(1)
        await self.service.cache_missing_article_images_async(limit=1)
        row = self.image(1)
        self.assertEqual(row["ga_cache_status"], "cached")
        self.assertEqual(row["ga_cache_attempts"], 0)
        self.assertIsNone(row["ga_cache_next_retry_at"])
        self.assertEqual(self.images.calls, [])

    async def test_older_due_failure_precedes_recent_due_failure(self):
        self.add_image(1, "failed")
        self.add_image(2, "failed")
        with self.connection() as conn:
            conn.execute(text("UPDATE articles SET ga_cache_next_retry_at = '2001-01-01' WHERE id = 1"))
            conn.execute(text("UPDATE articles SET ga_cache_next_retry_at = '2000-01-01' WHERE id = 2"))
        await self.service.cache_missing_article_images_async(limit=1)
        self.assertEqual(self.images.calls, [2])

    def test_backoff_is_capped_for_long_lived_failures(self):
        row = article_services.image_cache_status_update(1, "failed", attempts=10000)
        delay = (row["ga_cache_next_retry_at"] - datetime.now(timezone.utc)).total_seconds()
        self.assertGreater(delay, 86300)
        self.assertLessEqual(delay, 86400)
