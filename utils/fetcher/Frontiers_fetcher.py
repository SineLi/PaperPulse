import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://www.frontiersin.org/journals/immunology/rss"
class FrontiersFetcher(RSSFetcher):
    def __init__(self):
        super().__init__(
            journal_name="Frontiers in Immunology", 
            feed_url=DEFAULT_FEED_URL,
            max_workers=8,
            max_pages=0
        )

    def _parse_entry(self, entry) -> Dict:
        return {
            'title': entry.get('title', 'No Title'),
            'link': entry.get('link', ''),
            'abstract': entry.get('description', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'doi': self._extract_doi(entry),
            'status': 'online'
        }

    def fetch_details(self, article):

        return None


if __name__ == "__main__":
    FrontiersFetcher().run()

