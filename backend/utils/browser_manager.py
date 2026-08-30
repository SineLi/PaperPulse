import asyncio
import logging
import os
import threading
from contextlib import asynccontextmanager
from typing import Any

from playwright.async_api import Browser as PlaywrightBrowser
from playwright.async_api import Playwright, async_playwright

logger = logging.getLogger(__name__)

BROWSER_POOL_SIZE = int(os.getenv("BROWSER_POOL_SIZE", "2"))
BROWSER_MAX_PAGES = int(os.getenv("BROWSER_MAX_PAGES", "4"))


class Browser:
    """管理一个 Playwright 浏览器实例及其当前页面计数。"""

    def __init__(self):
        self.browser: PlaywrightBrowser | None = None
        self.id = id(self)
        self.activate_pages = 0
        self.status = "idle"
        self.playwright: Playwright | None = None

    @property
    def is_connected(self) -> bool:
        return self.browser is not None and self.browser.is_connected()

    async def launch(self, playwright: Playwright | None = None) -> None:
        if playwright is not None:
            self.playwright = playwright
        if self.playwright is None:
            raise RuntimeError("Playwright instance is not initialized")
        if self.is_connected:
            return

        launch_task = asyncio.create_task(
            self.playwright.chromium.launch(
                headless=True,
                args=["--disable-blink-features=AutomationControlled"],
            )
        )
        try:
            self.browser = await asyncio.shield(launch_task)
        except asyncio.CancelledError:
            # 启动请求可能已创建 Chromium；等待拿到句柄并关闭后再传播取消。
            launch_result = await asyncio.gather(launch_task, return_exceptions=True)
            launched_browser = launch_result[0]
            if not isinstance(launched_browser, BaseException):
                close_task = asyncio.create_task(launched_browser.close())
                await asyncio.gather(close_task, return_exceptions=True)
            raise
        self.status = "idle"

    async def close(self, preserve_status: bool = False) -> None:
        browser = self.browser
        self.activate_pages = 0
        if not preserve_status:
            self.status = "closed"
        if browser is None:
            return

        close_task = asyncio.create_task(browser.close())
        try:
            await asyncio.shield(close_task)
        except asyncio.CancelledError:
            # Chromium 关闭一旦开始就必须收口，否则句柄会在取消后失去引用。
            await asyncio.gather(close_task, return_exceptions=True)
            if not close_task.cancelled() and close_task.exception() is None:
                self.browser = None
            raise
        else:
            self.browser = None

    async def get_browser_context(self, user_agent: str | None = None):
        if not self.is_connected:
            # BrowserManager 负责替换断连实例，避免多个页面协程在这里并发启动 Chromium。
            raise RuntimeError("browser_disconnected")
        if self.browser is None:
            raise RuntimeError("browser_unavailable")
        if user_agent:
            return await self.browser.new_context(user_agent=user_agent)
        return await self.browser.new_context()


class BrowserManager:
    """在一次抓取周期内共享并限制 Playwright 浏览器资源。"""

    def __init__(
        self,
        max_browsers: int = BROWSER_POOL_SIZE,
        max_browser_pages: int = BROWSER_MAX_PAGES,
    ):
        if max_browsers <= 0 or max_browser_pages <= 0:
            raise ValueError("browser pool limits must be positive")

        self.max_browsers = max_browsers
        self.max_browser_pages = max_browser_pages
        self.browser_pool: list[Browser] = []
        self.playwright: Playwright | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._lock: asyncio.Lock | None = None
        self._semaphore: asyncio.Semaphore | None = None

    def _bind_running_loop(self) -> None:
        loop = asyncio.get_running_loop()
        if self._loop is loop:
            return
        if self.browser_pool or self.playwright is not None:
            raise RuntimeError("BrowserManager cannot be shared by active event loops")

        # APScheduler 每轮通过 asyncio.run 创建新事件循环，因此关闭后需要重建异步原语。
        self._loop = loop
        self._lock = asyncio.Lock()
        self._semaphore = asyncio.Semaphore(self.max_browsers * self.max_browser_pages)

    async def init_browser_pool(self) -> None:
        self._bind_running_loop()
        lock = self._lock
        if lock is None:
            raise RuntimeError("BrowserManager lock is not initialized")

        async with lock:
            if self.playwright is not None and self.browser_pool:
                return

            playwright: Playwright | None = None
            browsers: list[Browser] = []
            try:
                playwright = await async_playwright().start()
                browsers = [Browser() for _ in range(self.max_browsers)]
                launch_results = await asyncio.gather(
                    *(browser.launch(playwright) for browser in browsers),
                    return_exceptions=True,
                )
                launch_error = next(
                    (result for result in launch_results if isinstance(result, BaseException)),
                    None,
                )
                if launch_error is not None:
                    raise RuntimeError("Failed to initialize browser pool") from launch_error

                self.playwright = playwright
                self.browser_pool = browsers
            except BaseException:
                # 初始化必须整体成功；部分启动的实例也要全部回收。
                await asyncio.gather(
                    *(browser.close() for browser in browsers),
                    return_exceptions=True,
                )
                if playwright is not None:
                    try:
                        await playwright.stop()
                    except Exception:
                        logger.exception("event=playwright_stop_failed_after_init")
                self.playwright = None
                self.browser_pool = []
                raise

    async def _acquire_browser(self) -> Browser:
        await self.init_browser_pool()
        lock = self._lock
        if lock is None:
            raise RuntimeError("BrowserManager lock is not initialized")

        while True:
            refreshable: Browser | None = None
            refreshing = False
            async with lock:
                available = [
                    browser
                    for browser in self.browser_pool
                    if browser.status in {"idle", "active"}
                    and browser.is_connected
                    and browser.activate_pages < self.max_browser_pages
                ]
                if available:
                    browser = min(available, key=lambda item: item.activate_pages)
                    browser.activate_pages += 1
                    browser.status = "active"
                    return browser

                refreshable = next(
                    (
                        browser
                        for browser in self.browser_pool
                        if browser.activate_pages == 0
                        and browser.status != "refreshing"
                        and (browser.status == "error" or not browser.is_connected)
                    ),
                    None,
                )
                refreshing = any(browser.status == "refreshing" for browser in self.browser_pool)

            if refreshable is not None:
                await self.refresh_browser(refreshable)
                continue
            if refreshing:
                await asyncio.sleep(0.05)
                continue
            raise RuntimeError("No available browsers in the pool")

    @asynccontextmanager
    async def _get_browser(self):
        yield await self._acquire_browser()

    @asynccontextmanager
    async def add_page(self, user_agent: str | None = None):
        await self.init_browser_pool()
        semaphore = self._semaphore
        if semaphore is None:
            raise RuntimeError("BrowserManager semaphore is not initialized")

        context: Any = None
        page: Any = None
        async with semaphore:
            async with self._get_browser() as browser:
                try:
                    context = await browser.get_browser_context(user_agent=user_agent)
                    page = await context.new_page()
                except BaseException as exc:
                    await self._close_page_resources(page, context)
                    should_refresh = await self._release_browser(browser, has_error=True)
                    if should_refresh:
                        await self.refresh_browser(browser)
                    if not isinstance(exc, asyncio.CancelledError):
                        logger.exception("event=browser_page_create_failed browser_id=%s", browser.id)
                    raise

                try:
                    yield page
                finally:
                    resource_error = await self._close_page_resources(page, context)
                    should_refresh = await self._release_browser(browser, has_error=resource_error)
                    if should_refresh:
                        await self.refresh_browser(browser)

    async def _close_page_resources(self, page: Any, context: Any) -> bool:
        resource_error = False
        if page is not None:
            try:
                await page.close()
            except Exception:
                resource_error = True
                logger.exception("event=browser_page_close_failed")
        if context is not None:
            try:
                await context.close()
            except Exception:
                resource_error = True
                logger.exception("event=browser_context_close_failed")
        return resource_error

    async def _release_browser(self, browser: Browser, has_error: bool) -> bool:
        lock = self._lock
        if lock is None:
            return False

        async with lock:
            if browser.activate_pages > 0:
                browser.activate_pages -= 1
            if has_error or not browser.is_connected:
                browser.status = "error"
            elif browser.status != "error":
                browser.status = "idle" if browser.activate_pages == 0 else "active"
            return browser.status == "error" and browser.activate_pages == 0

    async def refresh_browser(self, browser: Browser) -> None:
        lock = self._lock
        if lock is None:
            return

        async with lock:
            if browser not in self.browser_pool or browser.activate_pages > 0:
                return
            if browser.status == "refreshing":
                return
            browser.status = "refreshing"
            playwright = self.playwright

        replacement = Browser()
        try:
            # 保持 refreshing 状态直到替换完成，避免第二个协程再次刷新同一池槽。
            await browser.close(preserve_status=True)
            await replacement.launch(playwright)
        except BaseException as exc:
            if not isinstance(exc, asyncio.CancelledError):
                logger.exception("event=browser_refresh_failed browser_id=%s", browser.id)
            async with lock:
                if browser in self.browser_pool:
                    browser.status = "error"
            if isinstance(exc, asyncio.CancelledError):
                raise
            return

        close_replacement = False
        async with lock:
            if browser in self.browser_pool:
                index = self.browser_pool.index(browser)
                self.browser_pool[index] = replacement
            else:
                close_replacement = True
        if close_replacement:
            await replacement.close()

    async def close_all_browsers(self) -> None:
        self._bind_running_loop()
        lock = self._lock
        if lock is None:
            return

        async with lock:
            pool = self.browser_pool
            playwright = self.playwright
            self.browser_pool = []
            self.playwright = None

        try:
            close_results = await asyncio.gather(
                *(browser.close() for browser in pool),
                return_exceptions=True,
            )
            for browser, result in zip(pool, close_results):
                if isinstance(result, BaseException):
                    logger.error("event=browser_close_failed browser_id=%s detail=%s", browser.id, result)
            if playwright is not None:
                await playwright.stop()
        finally:
            # 彻底解除旧事件循环状态，允许下一轮 asyncio.run 复用全局管理器。
            self._loop = None
            self._lock = None
            self._semaphore = None


_browser_manager: BrowserManager | None = None
_browser_manager_lock = threading.Lock()


def get_browser_manager() -> BrowserManager:
    """返回进程内共享的浏览器管理器。"""

    global _browser_manager
    if _browser_manager is None:
        with _browser_manager_lock:
            if _browser_manager is None:
                _browser_manager = BrowserManager()
    return _browser_manager
