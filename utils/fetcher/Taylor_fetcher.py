import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://www.tandfonline.com/feed/rss/kaup20"
class TaylorFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Autophagy", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def _parse_entry(self, entry) -> Dict:
        return {
            'title': entry.get('title', 'No Title'),
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'doi': self._extract_doi(entry),
            'status': 'online'
        }

    def fetch_details(self, article):
        link = article.get('link')
        
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Authors
        author_nodes = tree.xpath('//a[@class="author"]')
        if author_nodes:
            info['authors'] = [node.text_content().replace('\xa0', ' ').strip() for node in author_nodes if node.text_content().strip() and node.text_content().replace('\xa0', ' ').strip() != '\\']

        # Abstract
        abstract_nodes = tree.xpath('//div[@id="abstractId1"]/p')
        if abstract_nodes:
            info['abstract'] = html.unescape(' '.join([node.text_content().strip() for node in abstract_nodes]))

        # graphical abstract
        ga_parts = tree.xpath('//div[@class="figureView"]//a//img/@src')
        if ga_parts:
            info['graphical_abstract'] = "https://www.tandfonline.com" + ga_parts[0]

        return info
    
    def _extract_doi(self, entry):
        return entry.get('dc_identifier', '').replace('doi:', '')

if __name__ == "__main__":
    TaylorFetcher().run()

