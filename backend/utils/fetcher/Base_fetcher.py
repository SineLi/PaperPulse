from threading import Lock
import os
import time
import html
import logging
import inspect
from abc import ABC, abstractmethod
import asyncio
from typing import List, Dict, Optional

import feedparser
import requests
from dateutil import parser, tz

from utils.browser_manager import BrowserManager, get_browser_manager

from services.article_services import ArticleService
from utils.logging_utils import log_event

logger = logging.getLogger(__name__)

# 定义常见的时区缩写映射
TZ_INFOS = {
    "PST": tz.gettz("America/Los_Angeles"),
    "PDT": tz.gettz("America/Los_Angeles"),
    "EST": tz.gettz("America/New_York"),
    "EDT": tz.gettz("America/New_York"),
    "CST": tz.gettz("America/Chicago"),
    "CDT": tz.gettz("America/Chicago"),
}
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RSS_FETCH_TIMEOUT_SECS = float(os.getenv("RSS_FETCH_TIMEOUT_SECS", "20"))
PLAYWRIGHT_GOTO_TIMEOUT_MS = int(os.getenv("PLAYWRIGHT_GOTO_TIMEOUT_MS", "60000"))
PLAYWRIGHT_ATTEMPTS = int(os.getenv("PLAYWRIGHT_ATTEMPTS", "3"))
PLAYWRIGHT_IDLE_WAIT_MS = int(os.getenv("PLAYWRIGHT_IDLE_WAIT_MS", "2000"))
FETCH_PHASE_WARN_AFTER_SECS = 5 * 60


class BaseFetcher(ABC):
    def __init__(self, journal_name: str, journal_id: Optional[int] = None, max_workers: int = 5, sleep_time: int = 0, max_pages: int = 10, user_agent: str = UA, browser_manager: BrowserManager | None = None):
        self.journal_name = journal_name
        self.journal_id = journal_id
        self.max_workers = max_workers
        self.max_pages = max_pages
        self.sleep_time = sleep_time
        self.service = ArticleService()
        self.user_agent = user_agent
        self.browser_manager = browser_manager or get_browser_manager()

        # 按链接暂存 Playwright 抓取诊断，供详情任务区分被拦截、普通错误和未知失败。
        self._fetch_meta: dict[str, dict[str, Optional[str]]] = {}
        self._fetch_meta_lock = Lock()

    @abstractmethod
    def fetch_list(self) -> List[Dict]:
        # 获取文章列表，返回包含初步信息的字典列表
        pass

    @abstractmethod
    async def fetch_details(self, article: Dict) -> Dict:
        pass

    def _set_fetch_meta(self, url: str, status: str, reason: Optional[str] = None):
        if not url:
            return
        with self._fetch_meta_lock:
            self._fetch_meta[url] = {"status": status, "reason": reason}

    def _pop_fetch_meta(self, url: str) -> Optional[dict[str, Optional[str]]]:
        if not url:
            return None
        with self._fetch_meta_lock:
            return self._fetch_meta.pop(url, None)

    def _is_blocked_message(self, message: str) -> bool:
        msg = (message or "").lower()
        hints = [
            "captcha",
            "cloudflare",
            "just a moment",
            "verify you are human",
            "access denied",
            "forbidden",
            "blocked",
            "challenge",
            "403",
            "429",
        ]
        return any(h in msg for h in hints)

    def _detect_block_reason(self, content: str, current_url: str = "") -> Optional[str]:
        text = (content or "").lower()
        page_hints = [
            "just a moment",
            "verify you are human",
            "access denied",
            "captcha",
            "cloudflare",
            "security check",
            "are you a robot",
            "bot detection",
            "enable javascript and cookies",
        ]
        for hint in page_hints:
            if hint in text:
                return f"content:{hint}"

        lower_url = (current_url or "").lower()
        url_hints = ["cdn-cgi", "challenge", "captcha", "bot"]
        for hint in url_hints:
            if hint in lower_url:
                return f"url:{hint}"

        return None

    def _article_label(self, article: Dict) -> str:
        return article.get("title") or article.get("link") or "unknown"

    async def _fetch_details_with_logging(self, article: Dict) -> Dict:
        article_label = self._article_label(article)
        link = article.get("link", "")
        log_event(
            logger,
            logging.INFO,
            "article_fetch_started",
            journal=self.journal_name,
            article=article_label,
            url=link,
        )
        return await self.fetch_details(article)

    async def _get_playwright_content(
        self,
        url: str,
        selector: Optional[str] = None,
        timeout: int = 10000,
        wait_until: str = "domcontentloaded",
    ) -> str:
        log_event(
            logger,
            logging.INFO,
            "playwright_fetch_started",
            journal=self.journal_name,
            url=url,
            selector=selector,
            wait_until=wait_until,
        )
        browser = None
        context = None
        page = None
        content = ""
        try:
            for i in range(PLAYWRIGHT_ATTEMPTS):
                async with self.browser_manager.add_page() as page:
                    try:
                        log_event(
                            logger,
                            logging.INFO,
                            "playwright_fetch_attempt_started",
                            journal=self.journal_name,
                            url=url,
                            attempt=i + 1,
                        )
                        await page.goto(url, timeout=PLAYWRIGHT_GOTO_TIMEOUT_MS, wait_until=wait_until)  # ty:ignore[invalid-argument-type]
                        if selector:
                            await page.wait_for_selector(selector, timeout=timeout)
                        else:
                            await page.wait_for_timeout(PLAYWRIGHT_IDLE_WAIT_MS)
                        content = await page.content()
                        block_reason = self._detect_block_reason(content, page.url)
                        if block_reason:
                            self._set_fetch_meta(url, "blocked", block_reason)
                        elif content.strip():
                            self._set_fetch_meta(url, "ok")
                        else:
                            self._set_fetch_meta(url, "unknown", "empty_content")
                        log_event(
                            logger,
                            logging.INFO,
                            "playwright_fetch_succeeded",
                            journal=self.journal_name,
                            url=url,
                            final_url=page.url,
                            attempt=i + 1,
                            status=self._fetch_meta.get(url, {}).get("status"),
                            content_length=len(content),
                        )
                        break
                    except Exception as e:
                        logger.exception(
                            "event=playwright_fetch_attempt_failed journal=%s url=%s attempt=%s detail=%s",
                            self.journal_name,
                            url,
                            i + 1,
                            e,
                        )
                        status = "blocked" if self._is_blocked_message(str(e)) else "error"
                        self._set_fetch_meta(url, status, str(e))
                        if i == PLAYWRIGHT_ATTEMPTS - 1:
                            break
                        await asyncio.sleep(2)
        except Exception as e:
            logger.exception(
                "event=playwright_fetch_unhandled_failure journal=%s url=%s detail=%s",
                self.journal_name,
                url,
                e,
            )
            self._set_fetch_meta(url, "error", str(e))
            raise
        finally:
            # 循环内没有明确记录状态时，用页面内容兜底标记，避免后续把失败误判为成功。
            if url:
                current_meta = self._pop_fetch_meta(url)
                if current_meta is None:
                    if content.strip():
                        self._set_fetch_meta(url, "ok")
                    else:
                        self._set_fetch_meta(url, "unknown", "empty_content")
                else:
                    self._set_fetch_meta(url, current_meta.get("status", "unknown"), current_meta.get("reason"))  # ty:ignore[invalid-argument-type]

            final_meta = self._fetch_meta.get(url, {})
            log_event(
                logger,
                logging.INFO,
                "playwright_fetch_completed",
                journal=self.journal_name,
                url=url,
                status=final_meta.get("status"),
                reason=final_meta.get("reason"),
                content_length=len(content),
            )
        return content

    async def _fetch_list(self) -> List[Dict]:
        if inspect.iscoroutinefunction(self.fetch_list):
            return await self.fetch_list()
        return await asyncio.to_thread(self.fetch_list)

    async def fetch_detail_at_index(self, papers_to_fetch: List[Dict], idx: int):
        """抓取一篇文章详情，并将详情及诊断状态原地写回批次数组。

        该方法同时供旧的 fetcher 内部并发路径和新的全局任务队列复用。文章级异常
        会转换为 _fetch_status/_fetch_fail_reason 而不继续抛出，确保一篇失败不会中断
        整批抓取；队列据此仍可完成批次，最终由入库逻辑决定是否保存该条记录。
        """

        paper = papers_to_fetch[idx]
        link = paper.get("link", "")
        article_label = self._article_label(paper)

        try:
            details = await self._fetch_details_with_logging(paper)
        except Exception as err:
            fetch_meta = self._pop_fetch_meta(link)
            if fetch_meta:
                paper["_fetch_status"] = fetch_meta.get("status", "error")
                paper["_fetch_fail_reason"] = fetch_meta.get("reason") or str(err)
            else:
                status = "blocked" if self._is_blocked_message(str(err)) else "error"
                paper["_fetch_status"] = status
                paper["_fetch_fail_reason"] = str(err)

            logger.exception(
                "event=article_fetch_failed journal=%s article=%s url=%s detail=%s",
                self.journal_name,
                article_label,
                link,
                err,
            )
        else:
            if details:
                paper.update(details)

            fetch_meta = self._pop_fetch_meta(link)
            if fetch_meta:
                paper["_fetch_status"] = fetch_meta.get("status", "unknown")
                reason = fetch_meta.get("reason")
                if reason:
                    paper["_fetch_fail_reason"] = reason
            elif details:
                paper["_fetch_status"] = "ok"
            else:
                paper["_fetch_status"] = "unknown"
                paper["_fetch_fail_reason"] = "empty_details"

            log_event(
                logger,
                logging.INFO,
                "article_fetch_completed",
                journal=self.journal_name,
                article=article_label,
                url=link,
                status=paper.get("_fetch_status"),
                detail_fields=len(details) if isinstance(details, dict) else 0,
                has_abstract=bool(paper.get("abstract")),
                has_graphical_abstract=bool(paper.get("graphical_abstract")),
            )
        finally:
            if self.sleep_time > 0:
                await asyncio.sleep(self.sleep_time)

    async def _fetch_details_concurrently(self, papers_to_fetch: List[Dict]):
        semaphore = asyncio.Semaphore(self.max_workers)

        async def run_one(idx: int):
            async with semaphore:
                await self.fetch_detail_at_index(papers_to_fetch, idx)

        tasks = [asyncio.create_task(run_one(i)) for i in range(len(papers_to_fetch))]
        for task in asyncio.as_completed(tasks):
            await task

    async def collect(self) -> List[Dict] | None:
        """阶段1：获取RSS列表 + 过滤已存在文章，返回待抓取详情的文章列表"""
        total_started_at = time.monotonic()
        papers_to_fetch: List[Dict] | None = None
        log_event(
            logger,
            logging.INFO,
            "fetcher_collect_started",
            journal=self.journal_name,
            journal_id=self.journal_id,
            max_workers=self.max_workers,
        )
        try:
            # 1. 获取初步列表
            phase_started_at = time.monotonic()
            log_event(logger, logging.INFO, "fetcher_list_started", journal=self.journal_name)
            papers = await self._fetch_list()
            log_event(
                logger,
                logging.INFO,
                "fetcher_list_completed",
                journal=self.journal_name,
                elapsed_secs=time.monotonic() - phase_started_at,
                article_count=len(papers),
            )
            if not papers:
                log_event(logger, logging.WARNING, "fetcher_no_articles", journal=self.journal_name)
                return None

            # 2. 过滤已存在的文章
            phase_started_at = time.monotonic()
            log_event(
                logger,
                logging.INFO,
                "fetcher_filter_started",
                journal=self.journal_name,
                candidate_count=len(papers),
            )
            papers_to_fetch = await asyncio.to_thread(self.service.article_filter, papers)
            log_event(
                logger,
                logging.INFO,
                "fetcher_filter_completed",
                journal=self.journal_name,
                elapsed_secs=time.monotonic() - phase_started_at,
                candidate_count=len(papers),
                new_count=len(papers_to_fetch),
            )

            if not papers_to_fetch:
                log_event(logger, logging.INFO, "fetcher_no_new_articles", journal=self.journal_name)
                return None

            return papers_to_fetch
        except Exception as e:
            logger.exception("event=fetcher_collect_failed journal=%s detail=%s", self.journal_name, e)
            # 空列表是正常业务结果，异常则交给主调度记录为期刊抓取失败。
            raise
        finally:
            total_elapsed = time.monotonic() - total_started_at
            
            log_event(
                logger,
                logging.WARNING if total_elapsed >= FETCH_PHASE_WARN_AFTER_SECS else logging.INFO,
                "fetcher_collect_completed",
                journal=self.journal_name,
                elapsed_secs=total_elapsed,
            )
        

    async def finalize(self, papers_to_record: List[Dict]):
        # 4. 统一日期格式
        phase_started_at = time.monotonic()
        log_event(
            logger,
            logging.INFO,
            "fetcher_date_normalization_started",
            journal=self.journal_name,
            article_count=len(papers_to_record),
        )
        for paper in papers_to_record:
            raw_date = paper.get('date')
            if raw_date:
                try:
                    # 传入 tzinfos 参数来识别 PST 等缩写
                    dt = parser.parse(str(raw_date), tzinfos=TZ_INFOS)
                    paper['date'] = dt.strftime('%Y-%m-%d')
                except Exception as e:
                    logger.exception(
                        "event=article_date_normalize_failed journal=%s article=%s raw_date=%s detail=%s",
                        self.journal_name,
                        self._article_label(paper),
                        raw_date,
                        e,
                    )
        log_event(
            logger,
            logging.INFO,
            "fetcher_date_normalization_completed",
            journal=self.journal_name,
            elapsed_secs=time.monotonic() - phase_started_at,
        )

        # 5. 插入数据库
        phase_started_at = time.monotonic()
        log_event(
            logger,
            logging.INFO,
            "fetcher_insert_started",
            journal=self.journal_name,
            article_count=len(papers_to_record),
        )
        try:
            await asyncio.to_thread(self.service.insert_articles, papers_to_record)
            log_event(
                logger,
                logging.INFO,
                "fetcher_insert_succeeded",
                journal=self.journal_name,
                article_count=len(papers_to_record),
            )
        except Exception as e:
            logger.exception("event=fetcher_insert_failed journal=%s detail=%s", self.journal_name, e)
            raise
        log_event(
            logger,
            logging.INFO,
            "fetcher_insert_completed",
            journal=self.journal_name,
            elapsed_secs=time.monotonic() - phase_started_at,
        )


class RSSFetcher(BaseFetcher):
    # 专门处理 RSS 源的基类
    def __init__(self, journal_name: str, feed_url: str, **kwargs):
        super().__init__(journal_name, **kwargs)
        self.feed_url = feed_url

    def fetch_list(self) -> List[Dict]:
        log_event(logger, logging.INFO, "rss_fetch_started", journal=self.journal_name, url=self.feed_url)
        try:
            response = requests.get(
                self.feed_url,
                headers={"User-Agent": self.user_agent},
                timeout=RSS_FETCH_TIMEOUT_SECS,
            )
            response.raise_for_status()
        except requests.RequestException as e:
            logger.exception("event=rss_fetch_failed journal=%s url=%s detail=%s", self.journal_name, self.feed_url, e)
            return []

        feed = feedparser.parse(response.content)
        if feed.bozo:
            logger.error(
                "event=rss_parse_failed journal=%s url=%s detail=%s",
                self.journal_name,
                self.feed_url,
                feed.bozo_exception,
            )
            return []

        papers = []
        for entry in feed.entries:
            # 调用钩子方法解析单条 entry
            try:
                paper = self._parse_entry(entry)
            except Exception as e:
                logger.exception(
                    "event=rss_entry_parse_failed journal=%s url=%s detail=%s",
                    self.journal_name,
                    self.feed_url,
                    e,
                )
                continue
            if paper:
                papers.append(paper)
        log_event(
            logger,
            logging.INFO,
            "rss_fetch_completed",
            journal=self.journal_name,
            url=self.feed_url,
            status_code=response.status_code,
            entry_count=len(feed.entries),
            parsed_count=len(papers),
        )
        return papers

    def _parse_entry(self, entry) -> Dict:
        return {
            'title': entry.get('title', 'No Title'),
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'authors': self._extract_authors(entry),
            'status': 'online'
        }

    def _parse_date(self, entry):
        pub_date = entry.get('published', entry.get('updated'))
        if pub_date:
            try: return parser.parse(pub_date, tzinfos=TZ_INFOS).strftime('%Y-%m-%d')
            except: pass
        return None

    def _extract_authors(self, entry):
        if 'authors' in entry:
            return [a.get('name', '').replace('\n', '') for a in entry.authors]
        elif 'author' in entry:
            return [entry.author]
        return []
    
    def _extract_doi(self, entry):
        if 'links' in entry:
            for link in entry.links:
                if 'doi.org' in link.get('href', ''):
                    doi = link['href'].split('doi.org/')[-1]
                    return doi
        if 'id' in entry and 'doi.org' in entry.id:
            doi = entry.id.split('doi.org/')[-1]
            return doi
        return None
