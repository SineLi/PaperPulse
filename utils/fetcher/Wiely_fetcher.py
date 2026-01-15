import html
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://onlinelibrary.wiley.com/feed/15214095/most-recent"
class WileyFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Advanced Materials", journal_id=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )

    def _parse_entry(self, entry) -> Dict:
        # 从 content:encoded 获取内容 (feedparser 将其映射到 content 列表)
        content_list = entry.get('content', [])
        content_html = content_list[1].get('value', '') if content_list else ""
        
        abstract = ""
        editor_summary = ""
        graphical_abstract = ""
        
        if content_html:
            try:
                # 使用 lxml 解析 HTML 字符串
                tree = lhtml.fromstring(content_html)
                
                # 获取元素节点，然后使用 text_content() 提取包含 sub/sup 等子标签的完整文本
                p_nodes = tree.xpath('//p[2]')
                abstract = p_nodes[0].text_content().replace('\n', ' ').strip() if p_nodes else ""
                
                graphical_abstract = tree.xpath('//img/@src')[0]

                p_nodes = tree.xpath('//p[1]')
                editor_summary = p_nodes[0].text_content().replace('\n', ' ').strip() if p_nodes else ""
            except Exception as e:
                print(f"Error parsing HTML content: {e}")

        return {
            'title': entry.get('title', 'No Title'),
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'authors': self._extract_authors(entry),
            'doi': self._extract_doi(entry),
            'abstract': abstract,
            'editor_summary': editor_summary,
            'graphical_abstract': graphical_abstract,
            'status': 'online'
        }

    def _extract_doi(self, entry):
        doi = entry.get('guid', '')
        if 'doi.org' in doi:
            return doi.split('doi.org/')[-1]
        return doi
    
    def fetch_details(self, article: Dict):
        # Wiley 文章页面通常不需要额外的 JS 渲染，直接返回空字符串
        return ""

if __name__ == "__main__":
    WileyFetcher().run()

