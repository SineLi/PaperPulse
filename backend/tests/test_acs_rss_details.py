import unittest
from unittest.mock import AsyncMock, patch

from utils.fetcher.ACS_fetcher import ACSFetcher


class ACSRSSDetailTests(unittest.IsolatedAsyncioTestCase):
    def make_fetcher(self, **kwargs):
        with patch('utils.fetcher.Base_fetcher.ArticleService'):
            return ACSFetcher(browser_manager=object(), **kwargs)

    def entry(self, summary):
        return {
            'title': '[ASAP] Lithium channels',
            'link': 'https://pubs.acs.org/jacsat/article/doi/10.1021/jacs.test/123/Lithium-channels',
            'prism_doi': '10.1021/jacs.test',
            'summary': summary,
        }

    async def test_complete_rss_article_finishes_without_browser_and_preserves_math(self):
        fetcher = self.make_fetcher()
        fetcher._get_playwright_content = AsyncMock(side_effect=AssertionError('unneeded browser request'))
        paper = fetcher._parse_entry(self.entry(
            '<img src="https://cdn.example/ga.png?x=1&amp;y=2" />'
            '<span class="paragraphSection"><div class="boxTitle">Abstract</div>'
            'Selective Li<sup>+</sup> transport with H<sub>2</sub>O &amp; salt.</span>'
        ))

        await fetcher.fetch_detail_at_index([paper], 0)

        fetcher._get_playwright_content.assert_not_awaited()
        self.assertEqual(paper['abstract'], 'Selective Li+ transport with H2O & salt.')
        self.assertEqual(paper['graphical_abstract'], 'https://cdn.example/ga.png?x=1&y=2')
        self.assertEqual(paper['doi'], '10.1021/jacs.test')
        self.assertEqual(paper['_fetch_status'], 'ok')
        self.assertEqual(paper['_fetch_source'], 'acs_rss')

    async def test_unlabelled_teaser_still_uses_browser(self):
        fetcher = self.make_fetcher()
        fetcher._get_playwright_content = AsyncMock(return_value=(
            '<section class="abstract extra"><p>Actual page abstract.</p></section>'
        ))
        paper = fetcher._parse_entry(self.entry('<p>A journal alert. Read more online.</p>'))
        self.assertNotIn('abstract', paper)

        await fetcher.fetch_detail_at_index([paper], 0)

        fetcher._get_playwright_content.assert_awaited_once()
        self.assertEqual(paper['abstract'], 'Actual page abstract.')
        self.assertEqual(paper['_fetch_source'], 'acs_page')

    async def test_empty_abstract_label_does_not_skip_details(self):
        fetcher = self.make_fetcher()
        paper = fetcher._parse_entry(self.entry(
            '<img src="/ga.png"/><span class="paragraphSection"><div class="boxTitle">Abstract</div></span>'
        ))
        self.assertNotIn('abstract', paper)

    async def test_browser_first_keeps_valid_rss_when_page_is_blocked(self):
        fetcher = self.make_fetcher(prefer_rss=False)
        paper = fetcher._parse_entry(self.entry(
            '<span class="paragraphSection"><div class="boxTitle">Abstract</div>'
            'Publisher-provided full abstract.</span>'
        ))
        async def blocked(url, **kwargs):
            fetcher._set_fetch_meta(url, 'blocked', 'challenge')
            return '<title>Just a moment...</title>'
        fetcher._get_playwright_content = AsyncMock(side_effect=blocked)

        await fetcher.fetch_detail_at_index([paper], 0)

        fetcher._get_playwright_content.assert_awaited_once()
        self.assertEqual(paper['abstract'], 'Publisher-provided full abstract.')
        self.assertEqual(paper['_fetch_status'], 'ok')
        self.assertEqual(paper['_fetch_source'], 'acs_rss')

    async def test_browser_error_does_not_discard_valid_rss(self):
        fetcher = self.make_fetcher(prefer_rss=False)
        paper = fetcher._parse_entry(self.entry(
            '<h2>Abstract</h2><p>Publisher abstract.</p>'
        ))
        fetcher._get_playwright_content = AsyncMock(side_effect=RuntimeError('browser unavailable'))

        await fetcher.fetch_detail_at_index([paper], 0)

        self.assertEqual(paper['_fetch_status'], 'ok')
        self.assertEqual(paper['abstract'], 'Publisher abstract.')

    async def test_environment_can_select_browser_first(self):
        with patch.dict('os.environ', {'ACS_PREFER_RSS':'0'}):
            self.assertFalse(self.make_fetcher().prefer_rss)

    async def test_rss_first_preserves_individual_authors_from_combined_creator(self):
        fetcher = self.make_fetcher()
        fetcher._get_playwright_content = AsyncMock(side_effect=AssertionError('unexpected browser request'))
        entry = self.entry('<h2>Abstract</h2><p>Publisher abstract.</p>')
        expected = [
            'Harekrushna Behera', 'Tyler J. Duncan', 'Laxmicharan Samineni',
            'Hyeonji Oh', 'Chenhao Yao', 'Raman Dhiman', 'Siqi Wang',
            'Luke Hatch', 'Venkat Ganesan', 'Manish Kumar',
        ]
        entry['authors'] = [{'name': ', '.join(expected[:-1]) + ', and ' + expected[-1]}]
        paper = fetcher._parse_entry(entry)

        await fetcher.fetch_detail_at_index([paper], 0)

        self.assertEqual(paper['authors'], expected)
        self.assertEqual(paper['_fetch_status'], 'ok')
        fetcher._get_playwright_content.assert_not_awaited()

    async def test_two_authors_separated_by_and(self):
        fetcher = self.make_fetcher()
        self.assertEqual(fetcher._extract_authors({
            'authors': [{'name': 'Hang Li and Xuezhong Du'}],
        }), ['Hang Li', 'Xuezhong Du'])

    async def test_structured_authors_keep_commas_and_single_author_is_preserved(self):
        fetcher = self.make_fetcher()
        self.assertEqual(fetcher._extract_authors({
            'authors': [{'name': 'Doe, Alice'}, {'name': 'Smith, Bob'}],
        }), ['Doe, Alice', 'Smith, Bob'])
        self.assertEqual(fetcher._extract_authors({
            'authors': [{'name': 'Ehsan Rahimi'}],
        }), ['Ehsan Rahimi'])
        self.assertEqual(fetcher._extract_authors({}), [])

    async def test_author_field_fallback_splits_comma_separated_creators(self):
        fetcher = self.make_fetcher()
        self.assertEqual(fetcher._extract_authors({
            'author': 'Alice Example, Bob Example, Carol Example',
        }), ['Alice Example', 'Bob Example', 'Carol Example'])

    async def test_doi_metadata_is_preferred_over_article_url(self):
        fetcher = self.make_fetcher()
        self.assertEqual(fetcher._extract_doi({
            'prism_doi': 'doi:10.1021/jacs.correct',
            'links': [{'href':'https://pubs.acs.org/jacsat/article/doi/10.1021/jacs.wrong/123/title'}],
        }), '10.1021/jacs.correct')
        self.assertEqual(fetcher._extract_doi({
            'links':[{'href':'https://pubs.acs.org/jacsat/article/doi/10.1021/jacs.test/123/title?af=R'}],
        }), '10.1021/jacs.test')

    async def test_page_images_resolve_relative_urls_and_read_doi(self):
        fetcher = self.make_fetcher()
        fetcher._get_playwright_content = AsyncMock(return_value=(
            '<meta name="citation_doi" content="10.1021/jacs.test"/>'
            '<section class="extra abstract"><p>Page abstract.</p></section>'
            '<div class="fig-graphic extra"><img src="//cdn.example/ga.png"/></div>'
        ))
        details = await fetcher.fetch_details({'link':'https://pubs.acs.org/doi/10.1021/jacs.test'})
        self.assertEqual(details['graphical_abstract'], 'https://cdn.example/ga.png')
        self.assertEqual(details['doi'], '10.1021/jacs.test')


if __name__ == '__main__':
    unittest.main()
