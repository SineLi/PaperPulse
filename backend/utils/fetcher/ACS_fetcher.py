import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://pubs.acs.org/action/showFeed?type=axatoc&feed=rss&jc=jacsat"
class ACSFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Journal of the American Chemical Society", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def _parse_entry(self, entry) -> Dict:
        return {
            'title': entry.get('title', 'No Title').replace("[ASAP] ","").strip(),
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'authors': self._extract_authors(entry),
            'doi': self._extract_doi(entry),
            'status': 'online'
        }

    async def fetch_details(self, article):
        link = article.get('link')
        
        content = await self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_nodes = tree.xpath('//div[@id="abstractBox"]/p')
        if abstract_nodes:
            info['abstract'] = " ".join([node.text_content().strip() for node in abstract_nodes])

        # graphical abstract
        ga_parts = tree.xpath('//figure[starts-with(@id, "_i")]//img/@src')
        if ga_parts:
            info['graphical_abstract'] = "https://pubs.acs.org" + ga_parts[0]

        return info

if __name__ == "__main__":
    import asyncio
    asyncio.run(ACSFetcher().run())

