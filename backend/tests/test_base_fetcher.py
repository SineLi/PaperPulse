import unittest
import asyncio


class FakeBrowserManager:
    def __init__(self):
        self.closed = False

    async def close_all_browsers(self) -> None:
        self.closed = True


class StandaloneFetcher:
    def __init__(self, papers):
        self.papers = papers
        self.browser_manager = FakeBrowserManager()
        self.steps = []

    async def collect(self):
        self.steps.append("collect")
        return self.papers

    async def _fetch_details_concurrently(self, papers):
        self.steps.append("details")

    async def finalize(self, papers):
        self.steps.append("finalize")


class BaseFetcherRunTests(unittest.IsolatedAsyncioTestCase):
    async def test_cancelled_run_drains_detail_workers_before_closing_pool(self):
        from utils.fetcher.Base_fetcher import BaseFetcher

        class TrackingFetcher(StandaloneFetcher):
            _fetch_details_concurrently = BaseFetcher._fetch_details_concurrently

            def __init__(self):
                super().__init__([{"link": str(index)} for index in range(4)])
                self.max_workers = 2
                self.active = 0
                self.ready = asyncio.Event()

            async def fetch_detail_at_index(self, papers, idx):
                self.active += 1
                if self.active == 2:
                    self.ready.set()
                try:
                    await asyncio.Event().wait()
                finally:
                    self.active -= 1
                    if self.browser_manager.closed:
                        raise AssertionError("pool closed before detail worker exited")

        fetcher = TrackingFetcher()
        parent = asyncio.create_task(BaseFetcher.run(fetcher))
        await asyncio.wait_for(fetcher.ready.wait(), timeout=1)
        parent.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await parent
        self.assertEqual(fetcher.active, 0)
        self.assertTrue(fetcher.browser_manager.closed)
        self.assertNotIn("finalize", fetcher.steps)

    async def test_run_executes_standalone_pipeline_and_closes_browser_manager(self):
        from utils.fetcher.Base_fetcher import BaseFetcher

        fetcher = StandaloneFetcher([{"link": "https://example.com/article"}])

        await BaseFetcher.run(fetcher)

        self.assertEqual(fetcher.steps, ["collect", "details", "finalize"])
        self.assertTrue(fetcher.browser_manager.closed)

    async def test_run_skips_details_for_empty_collection_and_still_closes(self):
        from utils.fetcher.Base_fetcher import BaseFetcher

        fetcher = StandaloneFetcher([])

        await BaseFetcher.run(fetcher)

        self.assertEqual(fetcher.steps, ["collect"])
        self.assertTrue(fetcher.browser_manager.closed)


if __name__ == "__main__":
    unittest.main()
