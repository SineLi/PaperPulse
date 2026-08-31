import asyncio
import importlib.util
import sys
import threading
import types
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch


class FakeResult:
    def mappings(self):
        return self

    def all(self):
        return [
            {
                "id": 1,
                "graphical_abstract": "https://example.com/1.png",
                "ga_cache_status": "pending",
            }
        ]


class FakeConnection:
    def execute(self, *args, **kwargs):
        return FakeResult()


@contextmanager
def fake_db_connection():
    yield FakeConnection()


class FakeImageService:
    def __init__(self):
        self.started = threading.Event()
        self.release = threading.Event()
        self.finished = threading.Event()

    def has_cached_image(self, article_id: int) -> bool:
        return False

    def cache_image(self, url: str, article_id: int) -> dict:
        self.started.set()
        self.release.wait()
        self.finished.set()
        return {"url": url, "path": f"{article_id}.webp", "status": "cached", "error": None}


def load_article_service_class():
    sqlalchemy = types.ModuleType("sqlalchemy")
    sqlalchemy.text = lambda query: query
    database = types.ModuleType("db.database")
    database.get_db_connection = fake_db_connection
    image_service = types.ModuleType("services.image_service")
    image_service.ImageService = FakeImageService

    module_path = Path(__file__).resolve().parents[1] / "services" / "article_services.py"
    spec = importlib.util.spec_from_file_location("article_services_cancellation_test", module_path)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(
        sys.modules,
        {
            "sqlalchemy": sqlalchemy,
            "db.database": database,
            "services.image_service": image_service,
        },
    ):
        spec.loader.exec_module(module)
    return module.ArticleService


class ArticleServiceCancellationTests(unittest.IsolatedAsyncioTestCase):
    async def test_parent_cancellation_waits_for_image_executor_cleanup(self):
        article_service_class = load_article_service_class()
        service = article_service_class()
        status_updates = []
        service._update_ga_cache_statuses = status_updates.extend

        backfill = asyncio.create_task(
            service.cache_missing_article_images_async(
                limit=1,
                scan_limit=1,
                executor_timeout_secs=60,
            )
        )
        await asyncio.to_thread(service.image_service.started.wait)
        backfill.cancel()
        await asyncio.sleep(0)
        self.assertFalse(backfill.done())

        service.image_service.release.set()
        with self.assertRaises(asyncio.CancelledError):
            await backfill

        self.assertTrue(service.image_service.finished.is_set())
        self.assertEqual(status_updates, [])


if __name__ == "__main__":
    unittest.main()
