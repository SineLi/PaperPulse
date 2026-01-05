import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://rss.sciencedirect.com/publication/science/03088146"
class ElsevierFetcher(RSSFetcher):
    def __init__(self):
        super().__init__(
            journal_name="Food Chemistry", 
            feed_url=DEFAULT_FEED_URL,
            max_workers=8,
            max_pages=0
        )

    def _parse_entry(self, entry) -> Dict:
        return {
            'title': entry.get('title', 'No Title'),
            'link': entry.get('link', ''),
            'journal': self.journal_name,
            'date' : 
            lhtml.fromstring(entry.get('summary', '')).xpath('//p[1]/text()[contains(., "Publication date:")]')[0].split("Publication date:")[-1].strip() if "Publication date:" in entry.get('summary', "") else "",
            'status': 'online'
        }

    def fetch_details(self, article):
        link = article.get('link')
        
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}
        # DOI
        doi_parts = tree.xpath('//a[contains(@class,"doi")]/@href')
        if doi_parts:
            info['doi'] = doi_parts[0].replace("https://doi.org/","").strip()

        # Authors
        authors_parts = tree.xpath('//div[@id="author-group"]//button//text()[not(ancestor::sup)]')
        authors = [a.strip() for a in authors_parts if a.strip()]
        if authors:
            info['authors'] = authors

        # editorial summary
        ed_summary_parts = tree.xpath('//div[@class="abstract author-highlights"]//text()')
        if ed_summary_parts:
            info['editor_summary'] = html.unescape(' '.join([p.strip() for p in ed_summary_parts if p.strip()]))

        # Abstract
        abstract_parts = tree.xpath('//div[@class="abstract author"]/p//text()[not(ancestor::h2)]')
        if abstract_parts:
            info['abstract'] = html.unescape(' '.join([p.strip() for p in abstract_parts if p.strip()]))

        # graphical abstract
        ga_parts = tree.xpath('//div[@class="abstract graphical"]//ol/li[1]/a/@href') if tree.xpath('//div[@class="abstract graphical"]//ol/li[1]/a/@href') else tree.xpath('//div[@class="abstract graphical"]//img/@src')
        if ga_parts:
            info['graphical_abstract'] = ga_parts[0]

        return info

if __name__ == "__main__":
    ElsevierFetcher().run()

