import logging
import asyncio
from contextlib import asynccontextmanager
from playwright.async_api import async_playwright
from playwright.async_api._generated import Playwright as AsyncPlaywright
import threading

from utils.logging_utils import log_event

logger = logging.getLogger(__name__)

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

class Browser:
    # Browser类，负责管理Playwright浏览器实例的生命周期，包括启动、关闭和获取浏览器实例。
    def __init__(self):
        self.browser = None
        self.id = id(self)
        self.activate_pages = 0
        self.status = "idle"  # idle, active, error
        self.playwright: AsyncPlaywright | None = None
        

    async def launch(self, playwright: AsyncPlaywright | None = None):
        if playwright:
            self.playwright = playwright
        if not self.playwright:
            raise Exception("Playwright instance is not initialized")
        self.browser = await self.playwright.chromium.launch(headless=True,args=['--disable-blink-features=AutomationControlled'])


    async def close(self):
        if self.browser:
            await self.browser.close()

    async def get_browser_context(self):
        if not self.browser:
            await self.launch(self.playwright)
        
        if not self.browser:
            raise Exception("Failed to launch browser")

        return await self.browser.new_context()

class BrowserManager:
    # BrowserManager类，负责管理多个Browser实例的池化，提供获取和释放浏览器实例的方法，以支持并发访问。
    def __init__(self):
        self.max_browsers = 5
        self.browser_pool: list[Browser] = []  # 明确类型
        self.max_browser_pages = 32
        self.semaphore = asyncio.Semaphore(self.max_browsers * self.max_browser_pages)
        self.playwright : AsyncPlaywright | None = None
        self.lock = asyncio.Lock()

    async def init_browser_pool(self):
        async with self.lock:
            if self.playwright is not None and self.browser_pool:
                return

            playwright: AsyncPlaywright | None = None
            browsers: list[Browser] = []
            try:
                playwright = await async_playwright().start()
                browsers = [Browser() for _ in range(self.max_browsers)]
                await asyncio.gather(*(browser.launch(playwright) for browser in browsers))

                self.playwright = playwright
                self.browser_pool = browsers
            except Exception:
                # 如果在初始化过程中发生异常，确保所有已启动的浏览器实例都被正确关闭，并且Playwright实例也被停止，以避免资源泄漏。
                for browser in browsers:
                    try:
                        await browser.close()
                    except Exception:
                        pass

                if playwright is not None:
                    try:
                        await playwright.stop()
                    except Exception:
                        pass

                self.playwright = None
                self.browser_pool = []
                raise

    @asynccontextmanager
    async def _get_browser(self):
        browser: Browser | None = None

        if not self.browser_pool:
            await self.init_browser_pool()
        
        async with self.lock:  # 使用锁确保在获取浏览器实例时的线程安全
            idle_browsers = [b for b in self.browser_pool if b.status == "idle"]
            if idle_browsers:
                browser = min(idle_browsers, key=lambda b: b.activate_pages)
            else:
                available_browsers = [b for b in self.browser_pool if b.activate_pages < self.max_browser_pages]
                browser = min(available_browsers, key=lambda b: b.activate_pages) if available_browsers else None

            if browser is None:  # 先判空，再访问属性
                raise Exception("No available browsers in the pool")

            browser.activate_pages += 1
            browser.status = "active"

        try:
            yield browser
        finally:            pass

    @asynccontextmanager
    async def add_page(self):
        context = None
        page = None
        async with self.semaphore:  # 使用信号量控制并发访问，确保同时访问的浏览器实例数量不超过设定的最大值。
            async with self._get_browser() as browser:
                try:
                    context = await browser.get_browser_context()
                    page = await context.new_page()
                    # await page.goto(url)

                    try:
                        yield page
                    finally:
                        await page.close()
                        await context.close()
                        async with self.lock:
                            if browser.activate_pages > 0:
                                browser.activate_pages -= 1
                            if browser.activate_pages == 0:
                                browser.status = "idle"
                except Exception as e:
                    if page:
                        await page.close()
                    if context:
                        await context.close()
                    async with self.lock:
                        if browser.activate_pages > 0:
                            browser.activate_pages -= 1
                        browser.status = "error"
                    logger.error(f"Error in add_page: {e}")
                    raise
    
    async def refresh_browser(self, browser:Browser):
        async with self.lock:
            if browser.activate_pages > 0:
                logger.warning(f"Browser {browser.id} is active with {browser.activate_pages} pages, cannot refresh now.")
                return
            browser.status = "refreshing"
        await browser.close()
        async with self.lock:
            self.browser_pool.remove(browser)
            new_browser = Browser()
        await new_browser.launch(self.playwright)
        
        async with self.lock:
            new_browser.status = "idle"        
            self.browser_pool.append(new_browser)


    async def close_all_browsers(self):
        pool = self.browser_pool.copy()  # 复制列表以避免在迭代时修改原列表
        async with self.lock:
            self.browser_pool.clear()  # 清空浏览器池，防止在关闭过程中有新的浏览器被添加
        for browser in pool:
            try:
                await browser.close()
            except Exception as e:
                logger.error(f"Error closing browser {browser.id}: {e}")
        if self.playwright:
            await self.playwright.stop()
