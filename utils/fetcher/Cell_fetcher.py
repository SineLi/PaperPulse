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
            title_parts = div.xpath('.//h3/a//text()')
            title = "".join([t.strip() for t in title_parts if t.strip()])
            
            link_parts = div.xpath('.//h3/a/@href')
            link = 'https://www.cell.com' + link_parts[0] if link_parts else None

            authors_parts = div.xpath('.//li//ul/li//text()[not(ancestor::nav)]')
            authors = [a.strip() for a in authors_parts if a.strip()]

            editors_summary_parts = div.xpath('.//div/ul/li/div/div[2]/div/div[2]/div[2]/div[last()]//text()')
            editors_summary = " ".join([e.strip() for e in editors_summary_parts if e.strip()])

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
        abstract_parts = tree.xpath('//*[@id="author-abstract"]/div//text()')
        if abstract_parts:
            info['abstract'] = html.unescape(' '.join([p.strip() for p in abstract_parts if p.strip()]))

        # Graphical Abstract
        ga_parts = tree.xpath('//*[@id="graphical-abstract"]//a/@href')
        if ga_parts:
            info['graphical_abstract'] = "https://www.cell.com" + ga_parts[0]

        # DOI
        doi_parts = tree.xpath('//span[@class="doi"]/a/text()')
        if doi_parts:
            doi_text = ''.join(doi_parts).strip()
            info['doi'] = doi_text if doi_text else None

        # Date
        date_parts = tree.xpath('//span[@class="meta-panel__onlineDate"]/text()')
        if date_parts:
            info['date'] = ''.join(date_parts).strip()

        return info

if __name__ == "__main__":
    CellFetcher().run()
