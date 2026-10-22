"""Opt-in smoke tests against the real publisher endpoints.

These tests are intentionally skipped unless ``RUN_LIVE_FETCHER_TESTS=1`` is
set.  They exercise collection and one detail request per supported fetcher,
but never call ``collect``/``finalize`` and therefore never touch the database.
"""

import os
import unittest

from utils.browser_manager import BrowserManager
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


RUN_LIVE_FETCHER_TESTS = os.getenv("RUN_LIVE_FETCHER_TESTS") == "1"


@unittest.skipUnless(
    RUN_LIVE_FETCHER_TESTS,
    "set RUN_LIVE_FETCHER_TESTS=1 to enable real network/browser tests",
)
class LivePublisherFetcherTests(unittest.IsolatedAsyncioTestCase):
    """Fetch one live item per publisher without performing persistence."""

    async def assert_live_fetcher(self, fetcher, *, requires_elsevier_key=False):
        try:
            papers = await fetcher._fetch_list()
            self.assertIsInstance(papers, list)
            self.assertGreater(
                len(papers),
                0,
                f"{fetcher.journal_name} returned no articles from {getattr(fetcher, 'feed_url', getattr(fetcher, 'list_url', ''))}",
            )

            first = papers[0]
            self.assertTrue(first.get("title"), "live item has no title")
            self.assertTrue(first.get("link"), "live item has no link")

            if requires_elsevier_key and not os.getenv("Elsevier_KEY"):
                self.skipTest("Elsevier live detail test requires Elsevier_KEY")

            details = await fetcher.fetch_details(first)
            self.assertIsInstance(details, dict)
        finally:
            await fetcher.browser_manager.close_all_browsers()

    async def test_nature(self):
        await self.assert_live_fetcher(NatureFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_cell(self):
        await self.assert_live_fetcher(CellFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_elsevier(self):
        await self.assert_live_fetcher(
            ElsevierFetcher(browser_manager=BrowserManager(1, 1)),
            requires_elsevier_key=True,
        )

    async def test_science_aaas(self):
        await self.assert_live_fetcher(ScienceFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_acs(self):
        await self.assert_live_fetcher(ACSFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_rsc(self):
        await self.assert_live_fetcher(RSCFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_wiley(self):
        await self.assert_live_fetcher(WileyFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_taylor_and_francis(self):
        await self.assert_live_fetcher(TaylorFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_mdpi(self):
        await self.assert_live_fetcher(MDPIFetcher(browser_manager=BrowserManager(1, 1)))

    async def test_frontiers(self):
        await self.assert_live_fetcher(FrontiersFetcher(browser_manager=BrowserManager(1, 1)))


if __name__ == "__main__":
    unittest.main()
