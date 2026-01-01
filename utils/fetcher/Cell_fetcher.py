import json
import html
import time
from playwright.sync_api import sync_playwright
from lxml import etree
from concurrent.futures import ThreadPoolExecutor, as_completed
from dateutil import parser
from services.article_services import Article, ArticleService

url = "https://www.cell.com/cell/newarticles"

service = ArticleService()

def fetch_page(url):
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        context = browser.new_context(
            viewport={'width': 1920, 'height': 1080},
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
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
        page.wait_for_selector("//*[@id=\"frmSearch\"]/div[1]/div/div[2]/div[2]", timeout=10000)
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
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
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

            info_dict = {'abstract': None, 'graphical_abstract': None, 'doi': None, 'date': None}

            abstract_parts = tree.xpath('//*[@id="author-abstract"]/div//text()')
            if abstract_parts:
                abstract_text = ''.join(abstract_parts).strip()
                info_dict['abstract'] = html.unescape(abstract_text) if abstract_text else None

            graphical_abstract_parts = tree.xpath('//*[@id="graphical-abstract"]//a/@href')
            if graphical_abstract_parts:
                info_dict['graphical_abstract'] = 'https://www.cell.com' + graphical_abstract_parts[0]

            doi_parts = tree.xpath('//span[@class="doi"]/a/text()')
            if doi_parts:
                doi_text = ''.join(doi_parts).strip()
                info_dict['doi'] = doi_text if doi_text else None
            
            date_parts = tree.xpath('//span[@class="meta-panel__onlineDate"]/text()')
            if date_parts:
                date_text = ''.join(date_parts).strip()
                try:
                    parsed_date = parser.parse(date_text)
                    info_dict['date'] = parsed_date.strftime('%Y-%m-%d')
                except Exception:
                    info_dict['date'] = None

            return info_dict
        
    except Exception as e:
        print(f"Error fetching full info from {link}: {e}")
        return {}
    


def page_extractor(html_content,journal,max_workers=5):
    tree = etree.HTML(html_content)
    article_divs = tree.xpath(
        '//*[@id="frmSearch"]/div[1]/div/div[2]/div[2]/section'
    )
    papers = []

    for div in article_divs:
        title_parts = div.xpath('.//h3/a//text()')
        title = ''.join(title_parts).strip() if title_parts else None
        link =  div.xpath('.//h3/a/@href')

        authors = div.xpath('.//li//ul/li//text()[not(ancestor::nav)]')
        editor_summary = div.xpath('.//div/ul/li/div/div[2]/div/div[2]/div[2]/div[last()]//text()')

        norm_authors = [a.strip() for a in authors if a.strip()] if authors else []
        paper_info = Article(
            title=title,
            link='https://www.cell.com' + link[0] if link else None,
            doi=None,
            date=None,
            journal=journal,
            authors=norm_authors,
            editor_summary=''.join(editor_summary).strip() if editor_summary else None,
            structured_abstract=None,
            abstract=None,
            graphical_abstract=None,
            status='online'
        )
        papers.append(paper_info)
    paper_to_fetch = service.article_filter(papers)
    futures = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for idx, p in enumerate(paper_to_fetch):
            if p.get('link'):
                futures[executor.submit(get_full_info, p['link'])] = idx
        for future in as_completed(futures):
            idx = futures[future]
            try:
                info_dect = future.result()
            except Exception:
                info_dect = {}
            if info_dect:
                paper_to_fetch[idx]['abstract'] = info_dect.get('abstract') or paper_to_fetch[idx]['abstract']
                paper_to_fetch[idx]['graphical_abstract'] = info_dect.get('graphical_abstract') or paper_to_fetch[idx]['graphical_abstract']
                paper_to_fetch[idx]['doi'] = info_dect.get('doi') or paper_to_fetch[idx]['doi']
                paper_to_fetch[idx]['date'] = info_dect.get('date') or paper_to_fetch[idx]['date']
            time.sleep(10)  # To avoid overwhelming the server

    json_str = json.dumps(paper_to_fetch, ensure_ascii=False, indent=2)
    return json_str

def Cell_fetch(url,journal):
    html_content = fetch_page(url)
    articles_json = page_extractor(html_content,journal)

    return articles_json

if __name__ == '__main__':
    try:
        articles_json = Cell_fetch(url, "Cell")
        service.insert_articles(articles_json)
    except Exception as e:
        print(f"Error running Cell_fetcher main: {e}")