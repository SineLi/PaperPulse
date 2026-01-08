import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import BaseFetcher

DEFAULT_LINK = "https://www.cell.com/cell/newarticles"

class CellFetcher(BaseFetcher):
    def __init__(self, url=DEFAULT_LINK, name="Cell", workers=8, sleep_time=5):

        super().__init__(journal_name=name, max_workers=workers, sleep_time=sleep_time)
        
        self.list_url = url

    def fetch_list(self):
        content = self._get_playwright_content(self.list_url, selector="//*[@id=\"frmSearch\"]/div[1]/div/div[2]/div[2]")
        if not content: return []

        tree = lhtml.fromstring(content)
        article_divs = tree.xpath("//*[@id=\"frmSearch\"]/div[1]/div/div[2]/div[2]/section")
        
        papers = []
        for div in article_divs:
            title_nodes = div.xpath('.//h3/a')
            title = title_nodes[0].text_content().strip() if title_nodes else ""
            
            link_parts = div.xpath('.//h3/a/@href')
            link = 'https://www.cell.com' + link_parts[0] if link_parts else None

            authors_nodes = div.xpath('.//li//ul/li[not(ancestor::nav)]')
            authors = [node.text_content().strip() for node in authors_nodes if node.text_content().strip()]

            editors_summary_nodes = div.xpath('.//div/ul/li/div/div[2]/div/div[2]/div[2]/div[last()]')
            editors_summary = editors_summary_nodes[0].text_content().strip() if editors_summary_nodes else ""

            if title and link:
                papers.append({
                    'title': title,
                    'link': link,
                    'authors': authors,
                    'journal': self.journal_name,
                    'editor_summary': editors_summary,
                    'status': 'online'
                })
        return papers

    def fetch_details(self, article):
        link = article.get('link')
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_nodes = tree.xpath('//*[@id="author-abstract"]/div')
        if abstract_nodes:
            info['abstract'] = html.unescape(' '.join([node.text_content().strip() for node in abstract_nodes]))

        # Graphical Abstract
        ga_parts = tree.xpath('//*[@id="graphical-abstract"]//a/@href')
        if ga_parts:
            info['graphical_abstract'] = "https://www.cell.com" + ga_parts[0]

        # DOI
        doi_nodes = tree.xpath('//span[@class="doi"]/a')
        if doi_nodes:
            doi_text = doi_nodes[0].text_content().strip()
            info['doi'] = doi_text if doi_text else None

        # Date
        date_nodes = tree.xpath('//span[@class="meta-panel__onlineDate"]')
        if date_nodes:
            info['date'] = date_nodes[0].text_content().strip()

        return info

if __name__ == "__main__":
    CellFetcher().run()
