import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import BaseFetcher

DEFAULT_LINK = "https://www.nature.com/nature/research-articles"

class NatureFetcher(BaseFetcher):
    def __init__(self, url=DEFAULT_LINK, name="Nature", workers=8, pages=3): # 默认抓 3 页
        super().__init__(journal_name=name, max_workers=workers, max_pages=pages)
        self.list_url = url

    def fetch_list(self):
        all_papers = []
        
        for page in range(1, self.max_pages + 1):
            # 构造带页码的 URL
            page_url = f"{self.list_url}?page={page}"
            print(f"Fetching {self.journal_name} list page {page}...")
            
            content = self._get_playwright_content(page_url, selector="//*[@id=\"new-article-list\"]/div/ul")
            if not content:
                continue

            tree = lhtml.fromstring(content)
            article_divs = tree.xpath('//*[@id="new-article-list"]/div/ul/li/div/div')
            
            page_papers = []
            for div in article_divs:
                title_nodes = div.xpath('.//h3/a')
                title = title_nodes[0].text_content().replace('\xa0', ' ').strip() if title_nodes else ""
                
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
                    page_papers.append({
                        'title': title,
                        'link': link,
                        'doi': doi,
                        'date': date,
                        'journal': self.journal_name
                    })
            
            all_papers.extend(page_papers)
            print(f"Page {page}: found {len(page_papers)} articles.")
            
        return all_papers

    def fetch_details(self, article):
        link = article.get('link')
        content = self._get_playwright_content(link, wait_until="domcontentloaded")
        if not content: return {}

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_nodes = tree.xpath('//*[@id="Abs1-content"]')
        if abstract_nodes:
            info['abstract'] = html.unescape(abstract_nodes[0].text_content()).replace('\xa0', ' ').strip()

        # Graphical Abstract
        ga_parts = tree.xpath('//*[@id="figure-1"]//img/@src')
        if ga_parts:
            info['graphical_abstract'] = 'https:' + ga_parts[0] if ga_parts[0].startswith('//') else ga_parts[0]

        # Authors
        author_nodes = tree.xpath('//*[@class="c-article-header"]/header/ul[2]/li/a')
        if author_nodes:
            info['authors'] = [node.text_content().replace('\xa0', ' ').strip() for node in author_nodes if node.text_content().strip() and node.text_content().replace('\xa0', ' ').strip() != '\\']

        # Status
        status_parts = tree.xpath('//*[@id="content"]/main/article/div[1]/header/p[2]')
        info['status'] = 'pre-online' if status_parts else 'online'

        return info

if __name__ == "__main__":
    NatureFetcher().run()
