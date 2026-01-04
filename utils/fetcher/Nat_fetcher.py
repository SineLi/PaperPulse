import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import BaseFetcher

DEFAULT_LINK = "https://www.nature.com/nature/research-articles"

class NatureFetcher(BaseFetcher):
    def __init__(self, url=DEFAULT_LINK, name="Nature", workers=8):

        super().__init__(journal_name=name, max_workers=workers)
        
        self.list_url = url

    def fetch_list(self):
        content = self._get_playwright_content(self.list_url, selector="//*[@id=\"new-article-list\"]/div/ul")
        if not content: return []

        tree = lhtml.fromstring(content)
        article_divs = tree.xpath('//*[@id="new-article-list"]/div/ul/li/div/div')
        
        papers = []
        for div in article_divs:
            title_parts = div.xpath('.//h3/a//text()')
            title = "".join([t.strip() for t in title_parts if t.strip()])
            
            link_parts = div.xpath('.//h3/a/@href')
            link = "https://www.nature.com" + link_parts[0] if link_parts else None
            
            # DOI extraction from link if possible, or from page
            doi = None
            if link:
                parts = link.split('/')
                if len(parts) > 0:
                    doi = f"10.1038/{parts[-1]}"
            
            date_parts = div.xpath('.//time/@datetime')
            date = date_parts[0] if date_parts else None

            if title and link:
                papers.append({
                    'title': title,
                    'link': link,
                    'doi': doi,
                    'date': date,
                    'journal': self.journal_name
                })
        return papers

    def fetch_details(self, article):
        link = article.get('link')
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_parts = tree.xpath('//*[@id="Abs1-content"]//text()')
        if abstract_parts:
            info['abstract'] = html.unescape(' '.join([p.strip() for p in abstract_parts if p.strip()]))

        # Graphical Abstract
        ga_parts = tree.xpath('//*[@id="figure-1"]//img/@src')
        if ga_parts:
            info['graphical_abstract'] = 'https:' + ga_parts[0] if ga_parts[0].startswith('//') else ga_parts[0]

        # Authors
        author_parts = tree.xpath('//*[@class="c-article-header"]/header/ul[2]/li/a//text()')
        if author_parts:
            info['authors'] = [a.strip() for a in author_parts if a.strip()]

        # Status
        status_parts = tree.xpath('//*[@id="content"]/main/article/div[1]/header/p[2]')
        info['status'] = 'pre-online' if status_parts else 'online'

        return info

if __name__ == "__main__":
    NatureFetcher().run()
