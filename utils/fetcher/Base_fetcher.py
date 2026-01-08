import json
import time
import html
from abc import ABC, abstractmethod
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Optional

import feedparser
from lxml import etree, html as lhtml
from playwright.sync_api import sync_playwright
from dateutil import parser, tz

from services.article_services import ArticleService, Article

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
class BaseFetcher(ABC):
    def __init__(self, journal_name: str, journal_id: Optional[int] = None, max_workers: int = 5, sleep_time: int = 0, max_pages: int = 0, user_agent: str = UA):
        self.journal_name = journal_name
        self.journal_id = journal_id
        self.max_workers = max_workers
        self.max_pages = max_pages
        self.sleep_time = sleep_time
        self.service = ArticleService()
        self.user_agent = user_agent

    @abstractmethod
    def fetch_list(self) -> List[Dict]:
        # 获取文章列表，返回包含初步信息的字典列表
        pass

    @abstractmethod
    def fetch_details(self, article: Dict) -> Dict:
        # 获取单篇文章的详细信息（摘要、图片等）
        pass

    def _get_playwright_content(self, url: str, selector: Optional[str] = None, timeout: int = 10000, wait_until: str = "domcontentloaded"):
        # 通用的 Playwright 页面抓取工具
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True, args=['--disable-blink-features=AutomationControlled'])
            context = browser.new_context(user_agent=self.user_agent)
            page = context.new_page()
            
            content = ""
            for i in range(3):
                try:
                    page.goto(url, timeout=60000, wait_until=wait_until)
                    if selector:
                        page.wait_for_selector(selector, timeout=timeout)
                    else:
                        page.wait_for_timeout(2000)
                    content = page.content()
                    break
                except Exception as e:
                    print(f"Attempt {i+1} failed for {url}: {e}")
                    if i == 2: break
                    time.sleep(2)
            
            browser.close()
            return content

    def run(self):
        # 执行完整的抓取流程
        print(f"Starting fetcher for {self.journal_name}...")
        
        # 1. 获取初步列表
        papers = self.fetch_list()
        if not papers:
            print("No articles found.")
            return

        # 2. 过滤已存在的文章
        papers_to_fetch = self.service.article_filter(papers)
        print(f"Found {len(papers)} articles, {len(papers_to_fetch)} are new.")

        if not papers_to_fetch:
            return

        # 3. 并发抓取详情
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            futures = {executor.submit(self.fetch_details, p): i for i, p in enumerate(papers_to_fetch)}
            for future in as_completed(futures):
                idx = futures[future]
                try:
                    details = future.result()
                    if details:
                        papers_to_fetch[idx].update(details)
                except Exception as e:
                    print(f"Error fetching details for {papers_to_fetch[idx].get('link')}: {e}")
                if self.sleep_time > 0:
                    time.sleep(self.sleep_time)

        # 4. 统一日期格式
        for paper in papers_to_fetch:
            raw_date = paper.get('date')
            if raw_date:
                try:
                    # 传入 tzinfos 参数来识别 PST 等缩写
                    dt = parser.parse(str(raw_date), tzinfos=TZ_INFOS)
                    paper['date'] = dt.strftime('%Y-%m-%d')
                except Exception as e:
                    print(f"Date parse error: {raw_date} -> {e}")

        # 5. 插入数据库
        try:
            articles_json = json.dumps(papers_to_fetch, ensure_ascii=True, indent=2)
            self.service.insert_articles(articles_json)
            print(f"Successfully processed {self.journal_name}.")
            try: 
                json.loads(articles_json) 
            except Exception as e:
                print(f"Error in JSON serialization for {self.journal_name}: {e}")
        except Exception as e:
            print(f"Error inserting articles for {self.journal_name}: {e}")

class RSSFetcher(BaseFetcher):
    # 专门处理 RSS 源的基类
    def __init__(self, journal_name: str, feed_url: str, **kwargs):
        super().__init__(journal_name, **kwargs)
        self.feed_url = feed_url

    def fetch_list(self) -> List[Dict]:
        print(f"Fetching RSS: {self.feed_url}")
        feed = feedparser.parse(self.feed_url,agent='FreshRSS/1.24.3 (Linux; https://freshrss.org)')
        if feed.bozo:
            print(f"RSS Parse Error: {feed.bozo_exception}")
            return []

        papers = []
        for entry in feed.entries:
            # 调用钩子方法解析单条 entry
            paper = self._parse_entry(entry)
            if paper:
                papers.append(paper)
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

