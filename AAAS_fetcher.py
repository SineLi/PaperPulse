import requests
import json
from bs4 import BeautifulSoup
import re
import html
import time
from playwright.sync_api import sync_playwright
import asyncio
from lxml import etree

url = "https://www.science.org/toc/science/current"

def normalize_text(s):
    if s is None:
        return None
    return re.sub(r"\s+", " ", html.unescape(s)).strip()

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
        page.wait_for_selector("xpath=//*[@id=\"pb-page-content\"]/div/div[1]/main/section[2]/div/div[1]/div[2]/div[2]/div/section[6]", timeout=10000)
        content = page.content()
        browser.close()
        return content

def get_abstract(link):
    print(f"Fetching abstract from: {link}")
    if not link:
        return {}
    
    abs_link = link.replace('/doi/', '/doi/full/')
    
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
                    page.goto(abs_link)
                    page.wait_for_timeout(2000)
                    break
                except Exception as e:
                    print(f"Attempt {i+1} failed: {e}")
                    if i == 2:
                        raise e
                    time.sleep(2)
            content = page.content()
            browser.close()
            
            tree = etree.HTML(content)
            abstract_dict = {}
            
            section_ids = {'editor_summary': 'editor-abstract', 'structured_abstract': 'structured-abstract', 'abstract': 'abstract'}
            
            for key, section_id in section_ids.items():
                section = tree.xpath(f'//*[@id="abstracts"]//section[@id="{section_id}"]')
                if section:
                    section_text = normalize_text(''.join(section[0].xpath('.//text()[not(ancestor::h2)]')))
                    if section_text:
                        abstract_dict[key] = section_text
            
            figures = tree.xpath('//*[@id="abstracts"]//figure')

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

def page_extractor(html_content):
    tree = etree.HTML(html_content)
    article_divs = tree.xpath(
        '//*[@id="pb-page-content"]/div/div[1]/main/section[2]/div/div[1]/div[2]/div[2]/div/section[6]/div[position() >= 3]'
    )
    
    papers = []
    for div in article_divs:
        title_parts = div.xpath('.//h3/a//text()')
        title = normalize_text(''.join(title_parts)) if title_parts else None
        link = div.xpath('.//h3/a/@href')
        authors = div.xpath('./div/div[1]/div[2]/ul/li[2]/ul/li/span/text()')
        abstract = div.xpath('.//div[@class="highwire-abstract"]/p/text()')
        if not authors: continue
        
        abstract_dict = {}
        if link:
            full_link = 'https://www.science.org' + link[0]
            abstract_dict = get_abstract(full_link)
        
        norm_authors = [normalize_text(a) for a in authors if normalize_text(a)] if authors else []
        list_page_abs = normalize_text(abstract[0]) if abstract else None

        paper_info = {
            'title': title,
            'link': 'https://www.science.org' + link[0] if link else None,
            'authors': norm_authors,
            'editor_summary': abstract_dict.get('editor_summary'),
            'structured_abstract': abstract_dict.get('structured_abstract'),
            'abstract': abstract_dict.get('abstract') or list_page_abs,
            'graphical_abstract': abstract_dict.get('graphical_abstract')
        }
        papers.append(paper_info)
    papers = json.dumps(papers, ensure_ascii=False, indent=2)
    print(json.dumps(papers, ensure_ascii=False, indent=2))
    return papers
page_extractor(fetch_page(url))