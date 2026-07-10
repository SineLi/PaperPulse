import asyncio
import sys
import types
import unittest


class FakePage:
    def __init__(self):
        self.closed = False

    async def close(self):
        self.closed = True


class FakeContext:
    def __init__(self):
        self.closed = False

    async def new_page(self):
        return FakePage()

    async def close(self):
        self.closed = True


class FakeBrowserHandle:
    def __init__(self):
        self.connected = True
        self.fail_new_context = False

    def is_connected(self):
        return self.connected

    async def new_context(self):
        if self.fail_new_context:
            raise RuntimeError("context_failed")
        return FakeContext()

    async def close(self):
        self.connected = False


class FakeChromium:
    def __init__(self):
        self.launch_count = 0

    async def launch(self, **kwargs):
        self.launch_count += 1
        return FakeBrowserHandle()


class FakePlaywright:
    def __init__(self):
        self.chromium = FakeChromium()
        self.stopped = False

    async def stop(self):
        self.stopped = True


class FakePlaywrightStarter:
    instances: list[FakePlaywright] = []

    async def start(self):
        playwright = FakePlaywright()
        self.instances.append(playwright)
        return playwright


async_api = types.ModuleType("playwright.async_api")
async_api.Browser = FakeBrowserHandle
async_api.Playwright = FakePlaywright
async_api.async_playwright = FakePlaywrightStarter
playwright_package = types.ModuleType("playwright")
playwright_package.async_api = async_api
sys.modules.setdefault("playwright", playwright_package)
sys.modules.setdefault("playwright.async_api", async_api)

from utils.browser_manager import BrowserManager, get_browser_manager


class BrowserManagerTests(unittest.TestCase):
    def test_returns_process_singleton(self):
        self.assertIs(get_browser_manager(), get_browser_manager())

    def test_reuses_manager_across_asyncio_run_cycles(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=1)

        async def run_cycle():
            async with manager.add_page() as page:
                self.assertIsInstance(page, FakePage)
            await manager.close_all_browsers()

        asyncio.run(run_cycle())
        asyncio.run(run_cycle())

        self.assertIsNone(manager.playwright)
        self.assertEqual(manager.browser_pool, [])


class BrowserManagerAsyncTests(unittest.IsolatedAsyncioTestCase):
    async def test_page_usage_error_does_not_poison_browser(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=1)

        with self.assertRaisesRegex(ValueError, "article_failed"):
            async with manager.add_page():
                raise ValueError("article_failed")

        self.assertEqual(manager.browser_pool[0].status, "idle")
        self.assertEqual(manager.browser_pool[0].activate_pages, 0)
        await manager.close_all_browsers()

    async def test_replaces_browser_after_context_creation_failure(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=1)
        await manager.init_browser_pool()
        failed_browser = manager.browser_pool[0]
        failed_browser.browser.fail_new_context = True

        with self.assertRaisesRegex(RuntimeError, "context_failed"):
            async with manager.add_page():
                pass

        self.assertIsNot(manager.browser_pool[0], failed_browser)
        self.assertEqual(manager.browser_pool[0].status, "idle")
        await manager.close_all_browsers()


if __name__ == "__main__":
    unittest.main()
