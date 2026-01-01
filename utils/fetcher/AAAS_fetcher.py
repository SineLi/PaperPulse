import json
import html
import time
from playwright.sync_api import sync_playwright
from lxml import etree
from concurrent.futures import ThreadPoolExecutor, as_completed
from dateutil import parser
from services.article_services import Article, ArticleService

url = "https://www.science.org/journal/science/research?pageSize=50"

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
        page.wait_for_selector("//*[@id=\"pb-page-content\"]/div/div[1]/main/section/div/div[1]/div/div/div[1]", timeout=10000)
        content = page.content()
        browser.close()
        return content

def get_abstract(link):
    print(f"Fetching abstract from: {link}")
    if not link:
        return {}
    
    # abs_link = link.replace('/doi/', '/doi/full/')
    
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
                        browser.close()
                        raise e
                    time.sleep(5)
            content = page.content()
            browser.close()
            
            tree = etree.HTML(content)
            abstract_dict = {}
            
            section_ids = {'editor_summary': 'editor-abstract', 'structured_abstract': 'structured-abstract', 'abstract': 'abstract'}
            
            for key, section_id in section_ids.items():
                section = tree.xpath(f'//*[@id="abstracts"]//section[@id="{section_id}"]')
                if section:
                    section_text = ''.join(section[0].xpath('.//text()[not(ancestor::h2) and not(ancestor::h3)]')).strip()
                    if section_text:
                        abstract_dict[key] = section_text
            
            figures = tree.xpath('//figure[1]')

            if figures:
                try:
                    figure = figures[0]
                    img_src = figure.xpath('.//img/@src | .//img/@data-src | .//img/@data-lazy-src')
                    if img_src:
                        img_url = html.unescape(img_src[0])
                        if img_url.startswith('/'):
                            img_url = 'https://www.science.org' + img_url
                        elif not img_url.startswith('http'):
                            img_url = 'https://www.science.org/' + img_url
                        abstract_dict['graphical_abstract'] = img_url
                except Exception as e:
                    raise e
            
            return abstract_dict
        
    except Exception as e:
        raise e

def page_extractor(html_content,journal,max_workers=25):
    tree = etree.HTML(html_content)
    article_divs = tree.xpath(
        '//*[@id="pb-page-content"]/div/div[1]/main/section/div/div[1]/div/div/div[1]/div'
    )
    papers = []
    for div in article_divs:
        title_parts = div.xpath('.//h2/a//text()')
        title = ''.join(title_parts).strip() if title_parts else None
        link = div.xpath('.//h2/a/@href')
        authors = div.xpath('.//li/span//text()')
        date = parser.parse(div.xpath('.//time/text()')[0]).strftime('%Y-%m-%d') if div.xpath('.//time/text()') else None
        doi = None
        if link:
            parts = link[0].split('/')
            if len(parts) > 0:
                doi = parts[-2] + '/' + parts[-1]

        norm_authors = [a.strip() for a in authors if a.strip()] if authors else []
        paper_info = Article(
            title=title,
            link='https://www.science.org' + link[0] if link else None,
            doi=doi,
            date=date,
            journal=journal,
            authors=norm_authors,
            editor_summary=None,
            structured_abstract=None,
            abstract=None,
            graphical_abstract=None,
            status='online'
        )
        papers.append(paper_info)
    paper_to_fetch = ArticleService().article_filter(papers)
    # 并发抓取每篇的完整摘要
    futures = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for idx, p in enumerate(paper_to_fetch):
            if p.get('link'):
                futures[executor.submit(get_abstract, p['link'])] = idx
        for future in as_completed(futures):
            idx = futures[future]
            try:
                abstract_dict = future.result()
            except Exception:
                abstract_dict = {}
            if abstract_dict:
                paper_to_fetch[idx]['editor_summary'] = abstract_dict.get('editor_summary') or paper_to_fetch[idx]['editor_summary']
                paper_to_fetch[idx]['structured_abstract'] = abstract_dict.get('structured_abstract') or paper_to_fetch[idx]['structured_abstract']
                paper_to_fetch[idx]['abstract'] = abstract_dict.get('abstract') or paper_to_fetch[idx]['abstract']
                paper_to_fetch[idx]['graphical_abstract'] = abstract_dict.get('graphical_abstract') or paper_to_fetch[idx]['graphical_abstract']

    json_str = json.dumps(paper_to_fetch, ensure_ascii=False, indent=2)
    return json_str

def AAAS_fetch(url,journal):
    html_content = fetch_page(url)
    articles_json = page_extractor(html_content, journal)

    return articles_json