import html
import logging
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher

logger = logging.getLogger(__name__)

DEFAULT_FEED_URL = "https://www.nature.com/nature.rss"
UA = "FreshRSS/1.24.3 (Linux; https://freshrss.org)"

class NatureFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Nature", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def _parse_entry(self, entry):
        # 优先获取 dc_title (通常是纯标题)，如果缺失则清理标准 title
        title = entry.get('dc_title', entry.get('title', 'No Title'))
        if title.startswith(self.journal_name) and ':' in title:
            title = title.split(':', 1)[-1].strip()

        return {
            'title': title,
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'authors': self._extract_authors(entry),
            'doi': entry.get('prism_doi', self._extract_doi(entry)),
        }
    
    def _extract_doi(self, entry):
        if 'doi' in entry:
            return entry['doi']
        
    async def fetch_details(self, article):
        link = article.get('link')
        content = await self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_nodes = tree.xpath('//*[@id="Abs1-content"]')
        if abstract_nodes:
            info['abstract'] = html.unescape(abstract_nodes[0].text_content()).replace('\xa0', ' ').strip()

        # Graphical Abstract
        ga_parts = tree.xpath('//*[@id="figure-1"]//img/@src')
        if ga_parts:
            info['graphical_abstract'] = 'https:' + ga_parts[0] if ga_parts[0].startswith('//') else ga_parts[0]

        # Status
        status_parts = tree.xpath('//*[@id="content"]/main/article/div[1]/header/p[2]')
        info['status'] = 'pre-online' if status_parts else 'online'

        return info

if __name__ == "__main__":
    import asyncio
    asyncio.run(NatureFetcher().run())
