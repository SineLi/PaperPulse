import json
import html
import time
from playwright.sync_api import sync_playwright
from lxml import etree
from concurrent.futures import ThreadPoolExecutor, as_completed
from dateutil import parser
from configs import Article

url = "https://www.nature.com/nature/research-articles"

def fetch_page(url):
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        context = browser.new_context(
            viewport={'width': 1920, 'height': 1080},
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        )
        page = context.new_page()
        for i in range(3):
            try:
                page.goto(url)
                page.wait_for_timeout(2000)
                break
            except Exception as e:
                print(f"Attempt {i+1} failed: {e}")
                if i == 2:
                    raise e
                time.sleep(2)
        page.wait_for_selector("//*[@id=\"new-article-list\"]/div/ul", timeout=10000)
        content = page.content()
        browser.close()
        return content
    
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
            abstract_parts = tree.xpath('//*[@id="Abs1-content"]//text()')
            if abstract_parts:
                abstract = ' '.join([part.strip() for part in abstract_parts if part.strip()])
                info_dict['abstract'] = html.unescape(abstract)
            
            ga_parts = tree.xpath('//*[@id="figure-1"]//img/@src')
            if ga_parts:
                info_dict['graphical_abstract'] = 'https:' + ga_parts[0]
            
            author_parts = tree.xpath('//*[@id="content"]/main/article/div[2]/header/ul[2]/li/a//text()')
            if author_parts:
                info_dict['authors'] = [author.strip() for author in author_parts if author.strip()]

            status_parts = tree.xpath('//*[@id="content"]/main/article/div[1]/header/p[2]')
            if status_parts:
                info_dict['status'] = 'pre-online'
            
            return info_dict
    except Exception as e:
        raise e

def page_extractor(html_content,max_workers=25):
    tree = etree.HTML(html_content)
    article_divs = tree.xpath(
        '//*[@id="new-article-list"]/div/ul/li/div/div'
    )
    papers = []

    for div in article_divs:
        title_parts = div.xpath('.//h3/a//text()')
        title = ''.join(title_parts).strip() if title_parts else None
        link = div.xpath('.//h3/a/@href')
        authors = div.xpath('.//li/span//text()')
        date = parser.parse(div.xpath('.//time/@datetime')[0]).strftime('%Y-%m-%d') if div.xpath('.//time/@datetime') else None

        link_url = 'https://www.nature.com' + link[0] if link else None
        doi = None
        if link_url:
            parts = link_url.split('/')
            if len(parts) > 0:
                doi = f"10.1038/{parts[-1]}"

        norm_authors = [a.strip() for a in authors if a.strip()] if authors else []
        paper_info = Article(
            title=title,
            link=link_url,
            doi=doi,
            date=date,
            journal=None,
            authors=norm_authors,
            editor_summary=None,
            structured_abstract=None,
            abstract=None,
            graphical_abstract=None,
            status='online'
        )
        papers.append(paper_info)

    futures = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for idx, p in enumerate(papers):
            if p.get('link'):
                futures[executor.submit(get_full_info, p['link'])] = idx
        for future in as_completed(futures):
            idx = futures[future]
            try:
                info_dect = future.result()
            except Exception:
                info_dect = {}
            if info_dect:
                papers[idx]['abstract'] = info_dect.get('abstract') or papers[idx]['abstract']
                papers[idx]['graphical_abstract'] = info_dect.get('graphical_abstract') or papers[idx]['graphical_abstract']
                papers[idx]['authors'] = info_dect.get('authors') or papers[idx]['authors']
                papers[idx]['status'] = info_dect.get('status') or papers[idx]['status']

    json_str = json.dumps(papers, ensure_ascii=False, indent=2)
    return json_str
page_extractor(fetch_page(url))