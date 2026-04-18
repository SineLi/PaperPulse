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
        self.browser = await self.playwright.chromium.launch(headless=True)


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
        self.browser_pool = []
        self.max_browser_pages = 32
        self.semaphore = asyncio.Semaphore(self.max_browsers * self.max_browser_pages)
        self.playwright : AsyncPlaywright | None = None

    async def init_browser_pool(self):
        self.playwright = await async_playwright().start()
        # 并发启动浏览器实例
        self.browser_pool = [Browser() for _ in range(self.max_browsers)]
        await asyncio.gather(*(browser.launch(self.playwright) for browser in self.browser_pool))

    @asynccontextmanager
    async def get_browser(self):
        if not self.browser_pool:
            await self.init_browser_pool()

        idle_browsers = [b for b in self.browser_pool if b.status == "idle"]
        if idle_browsers:
            browser = min(idle_browsers, key=lambda b: b.activate_pages)
        else:
            available_browsers = [b for b in self.browser_pool if b.activate_pages < self.max_browser_pages]
            browser = min(available_browsers, key=lambda b: b.activate_pages) if available_browsers else None

        if not browser:
            raise Exception("No available browsers in the pool")
        try:
            yield browser
        finally:            pass

    @asynccontextmanager
    async def add_page(self, url):
        async with self.semaphore:  # 使用信号量控制并发访问，确保同时访问的浏览器实例数量不超过设定的最大值。
            async with self.get_browser() as browser:
                try:
                    context = await browser.get_browser_context()
                    page = await context.new_page()
                    browser.activate_pages += 1
                    await page.goto(url)
                    browser.status = "active"
                    try:
                        yield page
                    finally:
                        await page.close()
                        await context.close()
                        browser.activate_pages -= 1
                        if browser.activate_pages == 0:
                            browser.status = "idle"
                except Exception as e:
                    logger.error(f"Error in add_page: {e}")
                    browser.status = "error"
    
    async def refresh_browser(self, browser:Browser):
        if browser.activate_pages > 0:
            logger.warning(f"Browser {browser.id} is active with {browser.activate_pages} pages, cannot refresh now.")
            return

        await browser.close()
        self.browser_pool.remove(browser)
        new_browser = Browser()
        await new_browser.launch(self.playwright)
        self.browser_pool.append(new_browser)

    async def close_all_browsers(self):
        for browser in self.browser_pool:
            await browser.close()
        self.browser_pool.clear()
        if self.playwright:
            await self.playwright.stop()