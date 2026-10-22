import asyncio
import unittest
from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import patch

from utils import main_fetcher


class FakePool:
    async def init_browser_pool(self):
        pass

    async def close_all_browsers(self):
        pass


class FakeResult:
    def mappings(self):
        return self

    def all(self):
        return [
            {"id": 1, "name": "A", "publisher": "test", "rss_url": "https://example.com/a", "official_url": None},
            {"id": 2, "name": "B", "publisher": "test", "rss_url": "https://example.com/b", "official_url": None},
        ]


class FakeConnection:
    def execute(self, *args):
        return FakeResult()


@contextmanager
def connection():
    yield FakeConnection()


class FakeFetcher:
    started = []

    def __init__(self, name, **kwargs):
        self.journal_name = name

    async def collect(self):
        count = 6 if self.journal_name == "A" else 1
        return [{"link": str(index)} for index in range(count)]

    async def fetch_detail_at_index(self, papers, index):
        self.started.append(self.journal_name)
        if self.journal_name == "A":
            await asyncio.sleep(1)
        papers[index]["_fetch_status"] = "ok"

    async def finalize(self, papers):
        pass


class MainFetcherQueueTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.offset_patch = patch.object(main_fetcher, "_next_journal", 0)
        self.offset_patch.start()
        self.addCleanup(self.offset_patch.stop)

    def test_interleaves_journals_and_rotates_next_cycle(self):
        batches = [SimpleNamespace(tasks=["A1", "A2", "A3"]), SimpleNamespace(tasks=["B1", "B2"])]
        self.assertEqual(main_fetcher.build_fair_article_queue(batches), ["A1", "B1", "A2", "B2", "A3"])
        self.assertEqual(main_fetcher.build_fair_article_queue(batches), ["B1", "A1", "B2", "A2", "A3"])

    async def test_later_journal_runs_after_repeated_short_cycle_budget(self):
        FakeFetcher.started = []
        with patch.object(main_fetcher, "get_db_connection", connection), patch.object(main_fetcher, "get_browser_manager", return_value=FakePool()), patch.object(main_fetcher, "PUBLISHER_FETCHER_MAP", {"test": FakeFetcher}), patch.object(main_fetcher, "ARTICLE_FETCH_EXECUTOR_WORKERS", 1):
            await main_fetcher.run_enabled_fetchers_async(executor_timeout_secs=0.02)
            await main_fetcher.run_enabled_fetchers_async(executor_timeout_secs=0.02)
        self.assertIn("B", FakeFetcher.started)
        self.assertEqual(FakeFetcher.started[0], "A")
