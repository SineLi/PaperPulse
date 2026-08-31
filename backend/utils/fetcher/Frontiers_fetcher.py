import html
import ssl
ssl._create_default_https_context = ssl._create_unverified_context
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://www.frontiersin.org/journals/immunology/rss"
class FrontiersFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Frontiers in Immunology", journal_id=None, **kwargs):
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
            'abstract': entry.get('description', ''),
            'authors': self._extract_authors(entry),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'doi': self._extract_doi(entry),
            'status': 'online'
        }

    async def fetch_details(self, article):
        link = article.get('link')
        
        content = await self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # graphical abstract
        ga_parts = tree.xpath('//*[@class="ArticleFigure"]//*[@class="FrontiersImage"]//img/@src') or tree.xpath('//*[@class="FigureDesc"]//img/@src')
        if ga_parts:
            info['graphical_abstract'] = ga_parts[0]

        return info
    
    def _extract_doi(self, entry):
        # Prefer explicit DOI fields and DOI URLs.  The first RSS ``link`` is
        # usually the article page, so treating every link as a DOI produces
        # values such as ``articles/123``.
        candidates = (
            entry.get('doi', ''),
            entry.get('prism_doi', ''),
            entry.get('dc_identifier', ''),
            entry.get('id', ''),
        )
        for candidate in candidates:
            value = (candidate or '').strip()
            if not value:
                continue
            if value.lower().startswith('doi:'):
                value = value[4:].strip()
            if 'doi.org/' in value:
                value = value.split('doi.org/', 1)[1]
            if value.startswith('10.'):
                return value

        for link in entry.get('links', []):
            href = (link.get('href', '') or '').strip()
            if 'doi.org/' in href:
                return href.split('doi.org/', 1)[1]
        return ''


if __name__ == "__main__":
    import asyncio
    asyncio.run(FrontiersFetcher().run())

