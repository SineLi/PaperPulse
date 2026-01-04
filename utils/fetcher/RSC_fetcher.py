import feedparser
from dateutil import parser
from lxml import html as lhtml
from services.article_services import ArticleService, Article
from playwright.sync_api import sync_playwright
import json
import time
from lxml import etree
import html
from concurrent.futures import ThreadPoolExecutor, as_completed

feed_url = "http://feeds.rsc.org/rss/cs"
service = ArticleService()

def parse_feed(url, journal_name):
    print(f"Fetching RSS: {url}")
    feed = feedparser.parse(url)
    
    if feed.bozo:
        print(f"RSS Parse Error: {feed.bozo_exception}")
        return []

    papers = []
    for entry in feed.entries:
        title = entry.get('title', 'No Title')
        link = entry.get('link', '')
        
        # 日期
        pub_date = entry.get('published', entry.get('updated'))
        formatted_date = None
        if pub_date:
            try:
                formatted_date = parser.parse(pub_date).strftime('%Y-%m-%d')
            except:
                pass

        # 作者
        authors = []
        if 'authors' in entry:
            authors = [a.get('name', '') for a in entry.authors]
        elif 'author' in entry:
            authors = [entry.author]

        # 摘要与图片
        summary_html = entry.get('summary', '')
        graphical_abstract = None
        
        if summary_html:
            try:
                tree = lhtml.fromstring(summary_html)
                # 提取图片
                imgs = tree.xpath('//img/@src')
                if imgs:
                    graphical_abstract = imgs[0]
                
                doi_text_list = tree.xpath('//b[contains(text(), "DOI")]/following-sibling::text()')
                if doi_text_list:
                    # 取第一个文本节点，例如 ": 10.1039/D4CS00479E, Tutorial Review"
                    raw_doi_text = doi_text_list[0].strip()
                    # 去掉开头的冒号和空格
                    if raw_doi_text.startswith(':'):
                        raw_doi_text = raw_doi_text[1:].strip()
                    # 提取逗号前的部分作为 DOI
                    doi = raw_doi_text.split(',')[0].strip()

            except Exception:
                pass

        article = Article(
            title=title,
            link=link,
            doi=doi,
            date=formatted_date,
            journal=journal_name,
            authors=authors,
            editor_summary=None,
            structured_abstract=None,
            abstract=None,
            graphical_abstract=graphical_abstract,
            status='online'
        )
        papers.append(article)
    
    return papers

def get_full_info(link):
    print(f"Fetching abstract from: {link}")
    if not link:
        return {}
    
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=True,
                args=['--disable-blink-features=AutomationControlled']
            )
            context = browser.new_context(
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            )
            page = context.new_page()
            for i in range(3):
                try:
                    # Increase timeout to 60s and wait for DOM content only to avoid timeouts on heavy assets
                    page.goto(link, timeout=60000, wait_until="domcontentloaded")
                    page.wait_for_timeout(2000)
                    break
                except Exception as e:
                    print(f"Attempt {i+1} failed: {e}")
                    if i == 2:
                        raise e
                    time.sleep(5)
            content = page.content()
            browser.close()

            tree = etree.HTML(content)

            info_dict = {'abstract': None, 'graphical_abstract': None, 'authors': [],'status': 'online'}
            abstract_parts = tree.xpath('//*[@class="capsule__text"]/p//text()')
            if abstract_parts:
                abstract = ' '.join([part.strip() for part in abstract_parts if part.strip()])
                info_dict['abstract'] = html.unescape(abstract)
            
            return info_dict
        
    except Exception as e:
        raise e
    
def RSC_fetch(url, journal):
    papers = parse_feed(url, journal)
    papers_to_fetch = service.article_filter(papers)
    max_workers = 8
    futures = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for idx, p in enumerate(papers_to_fetch):
            if p.get('link'):
                futures[executor.submit(get_full_info, p['link'])] = idx
        for future in as_completed(futures):
            idx = futures[future]
            try:
                info_dect = future.result()
            except Exception:
                info_dect = {}
            if info_dect:
                papers_to_fetch[idx]['abstract'] = info_dect.get('abstract') or papers_to_fetch[idx]['abstract']
    json_str = json.dumps(papers_to_fetch, ensure_ascii=False, indent=2)
    return json_str

if __name__ == "__main__":

    print(RSC_fetch(feed_url, "Chemical Society Reviews"))
