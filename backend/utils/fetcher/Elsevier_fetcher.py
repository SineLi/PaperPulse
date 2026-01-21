import html
import logging
from lxml import etree
from utils.fetcher.Base_fetcher import RSSFetcher, Dict
import requests

logger = logging.getLogger(__name__)

from API_KEYs import Elsevier_KEY

DEFAULT_FEED_URL = "https://rss.sciencedirect.com/publication/science/03088146"
API_ADDRESS = 'https://api.elsevier.com/content/article/pii/'

ns = {
    'def': 'http://www.elsevier.com/xml/svapi/article/dtd',
    'dc': 'http://purl.org/dc/elements/1.1/',
    'prism': 'http://prismstandard.org/namespaces/basic/2.0/',
    'ce': 'http://www.elsevier.com/xml/common/dtd',
    'xocs': 'http://www.elsevier.com/xml/xocs/dtd',
    'dcterms': 'http://purl.org/dc/terms/'
}


class ElsevierFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Food Chemistry", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def _parse_entry(self, entry) -> Dict:
        return {
            'title': entry.get('title', 'No Title'),
            'link': entry.get('link', '').replace("?dgcid=rss_sd_all", ""),
            'journal': self.journal_name,
            'status': 'online'
        }

    def _get_ga_url(self, pii):
        try:
            for gav in range(1,4):
                for resv in [2,1,3]:
                    for size in ['lrg','']:
                        url = f"https://ars.els-cdn.com/content/image/1-s{resv}.0-{pii}-ga{gav}_{size}.jpg"
                        response = requests.head(url, timeout=5)
                        if response.status_code == 200:
                            return url
                        else:
                            continue
        except Exception as e:
            logger.error(f"Error fetching graphical abstract for PII {pii}: {e}")

    def fetch_details(self, article):
        link = article.get('link')
        pii = link.split("/")[-1].split("?")[0]  # 提取 PII
        url = API_ADDRESS + "{" + pii + "}"
        headers = {
            'XSD': 'text/xml',
            'X-ELS-APIKey': Elsevier_KEY,
            'Accept': 'text/xml'
        }

        response = requests.get(url, headers=headers, timeout=15)
        if response.status_code != 200:
            logger.error(f"Failed to fetch details for {link}: {response.status_code}")
            return {}

        tree = etree.fromstring(response.content)
        info = {}
        # DOI
        doi_nodes = tree.xpath('//prism:doi', namespaces=ns)
        if doi_nodes:
            info['doi'] = doi_nodes[0].xpath("string()").replace("https://doi.org/","").strip()

        # Authors
        author_nodes = tree.xpath('//dc:creator', namespaces=ns)
        authors = [node.xpath("string()").strip() for node in author_nodes]
        authors = [a for a in authors if a]
        if authors:
            info['authors'] = authors

        # date
        date_nodes = tree.xpath('//prism:coverDate', namespaces=ns)
        if date_nodes:
            info['date'] = date_nodes[0].xpath("string()").strip()

        # Abstract
        abstract_nodes = tree.xpath('//dc:description', namespaces=ns)
        if abstract_nodes:
            info['abstract'] = html.unescape(abstract_nodes[0].xpath("string()").strip())

        # graphical abstract
        info['graphical_abstract'] = self._get_ga_url(pii)

        return info

if __name__ == "__main__":
    ElsevierFetcher().run()

