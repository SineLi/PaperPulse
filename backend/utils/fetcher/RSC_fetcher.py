import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher

DEFAULT_FEED_URL = "http://feeds.rsc.org/rss/cs"
class RSCFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Chemical Society Reviews", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def fetch_details(self, article):
        link = article.get('link')
        
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_nodes = tree.xpath('//*[@class="capsule__text"]/p')
        if abstract_nodes:
            info['abstract'] = html.unescape(' '.join([node.text_content().strip() for node in abstract_nodes]))

        # DOI
        doi_parts = tree.xpath('//meta[@name="citation_doi"]/@content')
        if doi_parts:
            info['doi'] = doi_parts[0]

        # graphical abstract
        ga_parts = tree.xpath('//div[@class="capsule__column-wrapper"]//img[1]/@src')
        if ga_parts:
            info['graphical_abstract'] = "https://pubs.rsc.org" + ga_parts[0]

        return info

if __name__ == "__main__":
    RSCFetcher().run()

