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
        self.pause_close = False
        self.close_started = asyncio.Event()
        self.release_close = asyncio.Event()
        self.close_completed = False

    def is_connected(self):
        return self.connected

    async def new_context(self):
        if self.fail_new_context:
            raise RuntimeError("context_failed")
        return FakeContext()

    async def close(self):
        if self.pause_close:
            self.close_started.set()
            await self.release_close.wait()
        self.connected = False
        self.close_completed = True


class FakeChromium:
    def __init__(self):
        self.launch_count = 0
        self.handles = []
        self.refresh_started = asyncio.Event()
        self.release_refresh = asyncio.Event()
        self.pause_refresh = False

    async def launch(self, **kwargs):
        self.launch_count += 1
        handle = FakeBrowserHandle()
        self.handles.append(handle)
        if self.pause_refresh and self.launch_count > 1:
            self.refresh_started.set()
            await self.release_refresh.wait()
        return handle


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
    async def test_refresh_cancellation_closes_new_browser_started_during_launch(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=1)
        await manager.init_browser_pool()
        browser = manager.browser_pool[0]
        chromium = manager.playwright.chromium
        chromium.pause_refresh = True
        browser.browser.connected = False

        refresh = asyncio.create_task(manager.refresh_browser(browser))
        await chromium.refresh_started.wait()
        refresh.cancel()
        await asyncio.sleep(0)
        self.assertFalse(refresh.done())

        chromium.release_refresh.set()
        with self.assertRaises(asyncio.CancelledError):
            await refresh

        self.assertTrue(chromium.handles[0].close_completed)
        self.assertTrue(chromium.handles[1].close_completed)
        self.assertEqual(browser.status, "error")
        await manager.close_all_browsers()

    async def test_refresh_cancellation_waits_for_old_browser_to_close(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=1)
        await manager.init_browser_pool()
        browser = manager.browser_pool[0]
        old_handle = browser.browser
        old_handle.pause_close = True
        old_handle.connected = False

        refresh = asyncio.create_task(manager.refresh_browser(browser))
        await old_handle.close_started.wait()
        refresh.cancel()
        await asyncio.sleep(0)
        self.assertFalse(refresh.done())

        old_handle.release_close.set()
        with self.assertRaises(asyncio.CancelledError):
            await refresh

        self.assertTrue(old_handle.close_completed)
        self.assertIsNone(browser.browser)
        self.assertEqual(browser.status, "error")
        await manager.close_all_browsers()

    async def test_disconnected_browser_is_refreshed_once_for_concurrent_requests(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=2)
        await manager.init_browser_pool()
        disconnected_browser = manager.browser_pool[0]
        chromium = manager.playwright.chromium
        chromium.pause_refresh = True
        disconnected_browser.browser.connected = False

        async def open_page():
            async with manager.add_page():
                pass

        first_request = asyncio.create_task(open_page())
        await chromium.refresh_started.wait()
        second_request = asyncio.create_task(open_page())
        await asyncio.sleep(0)

        # 刷新中的槽位不能再次启动 Chromium；第二个请求只能等待同一替换操作。
        self.assertEqual(chromium.launch_count, 2)
        chromium.release_refresh.set()
        await asyncio.gather(first_request, second_request)

        self.assertEqual(chromium.launch_count, 2)
        self.assertIsNot(manager.browser_pool[0], disconnected_browser)
        await manager.close_all_browsers()

    async def test_browser_does_not_relaunch_when_context_is_requested_after_disconnect(self):
        manager = BrowserManager(max_browsers=1, max_browser_pages=1)
        await manager.init_browser_pool()
        browser = manager.browser_pool[0]
        browser.browser.connected = False
        chromium = manager.playwright.chromium

        with self.assertRaisesRegex(RuntimeError, "browser_disconnected"):
            await browser.get_browser_context()

        self.assertEqual(chromium.launch_count, 1)
        await manager.close_all_browsers()
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
