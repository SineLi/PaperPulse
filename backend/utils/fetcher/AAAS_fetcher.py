import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher

DEFAULT_FEED_URL = "https://www.science.org/action/showFeed?type=axatoc&feed=rss&jc=science"
UA = "FreshRSS/1.24.3 (Linux; https://freshrss.org)"
class ScienceFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Science", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def _parse_entry(self, entry):
        # 优先获取 dc_title (通常是纯标题)，如果缺失则清理标准 title
        title = entry.get('dc_title', entry.get('title', 'No Title'))
        if title.startswith(self.journal_name) and ':' in title:
            title = title.split(':', 1)[-1].strip()

        return {
            'title': title,
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'authors': self._extract_authors(entry),
            'doi': entry.get('prism_doi', self._extract_doi(entry)),
            'status': 'online'
        }

    def _extract_authors(self, entry):
        if 'author' in entry:
            return [a.strip() for a in entry['author'].split(',')]
        return []
    
    def _extract_doi(self, entry):
        if 'doi' in entry:
            return entry['doi']

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
