import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import BaseFetcher

DEFAULT_LINK = "https://www.science.org/journal/science/research?pageSize=50"

class ScienceFetcher(BaseFetcher):
    def __init__(self, url=DEFAULT_LINK, name="Science", workers=8):

        super().__init__(journal_name=name, max_workers=workers)
        
        self.list_url = url

    def fetch_list(self):
        content = self._get_playwright_content(self.list_url, selector="//*[@id=\"pb-page-content\"]/div/div[1]")
        if not content: return []

        tree = lhtml.fromstring(content)
        article_divs = tree.xpath("//*[@id=\"pb-page-content\"]/div/div[1]/main/section/div/div[1]/div/div/div[1]/div")
        
        papers = []
        for div in article_divs:
            title_nodes = div.xpath('.//h2/a')
            title = title_nodes[0].text_content().strip() if title_nodes else ""
            
            link_parts = div.xpath('.//h2/a/@href')
            link = 'https://www.science.org' + link_parts[0] if link_parts else None
            
            date_nodes = div.xpath('.//time')
            date = date_nodes[0].text_content().strip() if date_nodes else None

            authors_nodes = div.xpath('.//li/span')
            authors = [node.text_content().strip() for node in authors_nodes]
            authors = [a for a in authors if a]

            doi = None
            if link:
                parts = link.split('/')
                if len(parts) > 0:
                    doi = parts[-2] + '/' + parts[-1]

            if title and link:
                papers.append({
                    'title': title,
                    'link': link,
                    'date': date,
                    'authors': authors,
                    'doi': doi,
                    'journal': self.journal_name,
                    'status': 'online'
                })
        return papers

    def fetch_details(self, article):
        link = article.get('link')
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstracts
        section_ids = {'editor_summary': 'editor-abstract', 'structured_abstract': 'structured-abstract', 'abstract': 'abstract'}
            
        for key, section_id in section_ids.items():
            section = tree.xpath(f'//*[@id="abstracts"]//section[@id="{section_id}"]')
            if section:
                section_text = ''.join(section[0].xpath('.//text()[not(ancestor::h2) and not(ancestor::h3)]')).strip()
                if section_text:
                    info[key] = section_text

        # Graphical Abstract
        ga_parts = tree.xpath('//figure[1]')
        if ga_parts:
            figure = ga_parts[0]
            img_src = figure.xpath('.//img/@src | .//img/@data-src | .//img/@data-lazy-src')
            if img_src:
                info['graphical_abstract'] = "https://www.science.org" + html.unescape(img_src[0])

        return info

if __name__ == "__main__":
    ScienceFetcher().run()
