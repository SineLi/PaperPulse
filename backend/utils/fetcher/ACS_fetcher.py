import os
import re
from urllib.parse import unquote, urljoin
from lxml import html as lhtml
from utils.fetcher.Base_fetcher import RSSFetcher, Dict

DEFAULT_FEED_URL = "https://pubs.acs.org/rss/jacsat/asap.xml"
class ACSFetcher(RSSFetcher):
    def __init__(self, url=DEFAULT_FEED_URL, name="Journal of the American Chemical Society", journal_id=None, prefer_rss=None, **kwargs):
        super().__init__(
            journal_name=name, 
            feed_url=url,
            journal_id=journal_id,
            **kwargs
        )
        self.prefer_rss = (
            os.getenv("ACS_PREFER_RSS", "1").strip().lower() not in {"0", "false", "no"}
            if prefer_rss is None else prefer_rss
        )

    def _parse_entry(self, entry) -> Dict:
        article = {
            'title': entry.get('title', 'No Title').replace("[ASAP] ","").strip(),
            'link': entry.get('link', ''),
            'date': self._parse_date(entry),
            'journal': self.journal_name,
            'authors': self._extract_authors(entry),
            'doi': self._extract_doi(entry),
            'status': 'online'
        }
        # Current ACS descriptions contain the full labelled abstract and TOC image.
        # Retain them before the detail stage instead of requesting the same data again.
        fragments = [entry.get('summary', '')]
        fragments.extend(item.get('value', '') for item in entry.get('content', []))
        for fragment in fragments:
            if not fragment:
                continue
            try:
                tree = lhtml.fragment_fromstring(fragment, create_parent='div')
            except (ValueError, lhtml.etree.ParserError):
                continue
            headings = tree.xpath(
                './/*[self::h2 or self::h3 or '
                'contains(concat(" ", normalize-space(@class), " "), " boxTitle ")]'
                '[translate(normalize-space(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", '
                '"abcdefghijklmnopqrstuvwxyz")="abstract"]'
            )
            sections = tree.xpath(
                './/*[contains(concat(" ", normalize-space(@class), " "), '
                '" paragraphSection ")]'
            )
            # A journal alert or editorial teaser is not a labelled article abstract.
            if not headings:
                continue
            for heading in headings:
                heading.drop_tree()
            abstract = re.sub(r'\s+', ' ', ' '.join(
                node.text_content() for node in (sections or [tree])
            )).strip()
            if not abstract:
                continue
            article['abstract'] = abstract
            images = tree.xpath('.//img/@src')
            if images:
                article['graphical_abstract'] = urljoin(article['link'], images[0])
            article['_fetch_source'] = 'acs_rss'
            break
        return article
    
    def _extract_doi(self, entry):
        for key in ('prism_doi', 'doi', 'dc_identifier', 'id', 'guid'):
            candidate = entry.get(key, '')
            if isinstance(candidate, str):
                match = re.search(r'10\.\d{4,9}/[^/\s?#<>]+', unquote(candidate))
                if match:
                    return match.group(0)
        for link in entry.get('links', []):
            match = re.search(r'10\.\d{4,9}/[^/\s?#<>]+', unquote(link.get('href', '')))
            if match:
                return match.group(0)
        return None

    async def fetch_details(self, article):
        link = article.get('link')
        rss_details = {
            key: article[key] for key in ('abstract', 'graphical_abstract', 'doi')
            if article.get(key)
        } if article.get('abstract') and article.get('_fetch_source') == 'acs_rss' else {}
        if rss_details:
            rss_details['_fetch_source'] = 'acs_rss'
            if self.prefer_rss:
                return rss_details

        try:
            content = await self._get_playwright_content(link, wait_until="domcontentloaded")
        except Exception:
            if not rss_details:
                raise
            self._set_fetch_meta(link, 'ok', 'acs_rss_fallback')
            return rss_details
        if not content:
            if rss_details:
                self._set_fetch_meta(link, 'ok', 'acs_rss_fallback')
            return rss_details

        tree = lhtml.fromstring(content)
        info = {}

        # Abstract
        abstract_nodes = tree.xpath(
            '//section[contains(concat(" ", normalize-space(@class), " "), " abstract ")]//p'
            ' | //*[@id="abstractBox"]//p'
        )
        if abstract_nodes:
            info['abstract'] = " ".join([node.text_content().strip() for node in abstract_nodes])

        # graphical abstract
        ga_parts = tree.xpath(
            '//div[contains(concat(" ", normalize-space(@class), " "), " fig-graphic ")]//img/@src'
            ' | //figure[starts-with(@id, "_i")]//img/@src'
        )
        if ga_parts:
            info['graphical_abstract'] = urljoin(link or 'https://pubs.acs.org/', ga_parts[0])

        doi_parts = tree.xpath('//meta[@name="citation_doi"]/@content')
        if doi_parts:
            info['doi'] = doi_parts[0]

        author_nodes = tree.xpath('//div[@class="al-author-name"]/a')
        if author_nodes:
            authors = []
            seen = set()
            for node in author_nodes:
                name = node.text_content().strip()
                if name and name not in seen:
                    seen.add(name)
                    authors.append(name)
            info['authors'] = authors

        if info.get('abstract'):
            info['_fetch_source'] = 'acs_page'
        elif rss_details:
            self._set_fetch_meta(link, 'ok', 'acs_rss_fallback')
            return rss_details
        return info

if __name__ == "__main__":
    import asyncio
    asyncio.run(ACSFetcher().run())

