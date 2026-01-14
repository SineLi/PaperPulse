import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher

DEFAULT_FEED_URL = "https://www.mdpi.com/rss/journal/foods"
UA = "FreshRSS/1.24.3 (Linux; https://freshrss.org)"
class MDPIFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Foods"):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            max_workers=8,
            max_pages=0,
            user_agent=UA
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
            'abstract': entry.get('summary', '').replace('\n', ' ').strip(),
            'status': 'online'
        }

    def fetch_details(self, article):
        link = article.get('link')
        
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}
        # 获取所有符合条件的第一个图片路径
        ga_parts = tree.xpath('(//div[@class="html-fig_img"]//img)[1]/@src')
        if ga_parts:
            img_url = ga_parts[0]
            info['graphical_abstract'] = img_url if img_url.startswith('http') else "https://www.mdpi.com" + img_url

        return info

if __name__ == "__main__":
    MDPIFetcher().run()

