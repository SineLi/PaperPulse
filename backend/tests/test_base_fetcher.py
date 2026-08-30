import unittest


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
