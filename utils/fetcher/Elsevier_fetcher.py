import html
from lxml import etree
from utils.fetcher.Base_fetcher import RSSFetcher, Dict
import requests

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
    def __init__(self):
        super().__init__(
            journal_name="Food Chemistry", 
            feed_url=DEFAULT_FEED_URL,
            max_workers=4,
            max_pages=0,
            sleep_time=1,
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
            print(f"Error fetching graphical abstract for PII {pii}: {e}")

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
            print(f"Failed to fetch details for {link}: {response.status_code}")
            return {}

        tree = etree.fromstring(response.content)
        info = {}
        # DOI
        doi_parts = tree.xpath('//prism:doi/text()', namespaces=ns)
        if doi_parts:
            info['doi'] = doi_parts[0].replace("https://doi.org/","").strip()

        # Authors
        authors_parts = tree.xpath('//dc:creator/text()', namespaces=ns)
        authors = [a.strip() for a in authors_parts if a.strip()]
        if authors:
            info['authors'] = authors

        # date
        date_parts = tree.xpath('//prism:coverDate/text()', namespaces=ns)
        if date_parts:
            info['date'] = date_parts[0].strip()

        # Abstract
        abstract_parts = tree.xpath('//dc:description/text()', namespaces=ns)
        if abstract_parts:
            info['abstract'] = html.unescape(' '.join([p.strip() for p in abstract_parts if p.strip()]))

        # graphical abstract
        info['graphical_abstract'] = self._get_ga_url(pii)

        return info

if __name__ == "__main__":
    ElsevierFetcher().run()

