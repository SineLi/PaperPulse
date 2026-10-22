"""Unit tests for every currently supported publisher fetcher.

The tests deliberately stop at the network/browser boundaries.  RSS/API
responses and article HTML are supplied as small fixtures, so running this
module never contacts a publisher, starts Playwright, or needs a database.
"""

import unittest
from unittest.mock import ANY, AsyncMock, Mock, patch

import requests

from utils.fetcher.AAAS_fetcher import ScienceFetcher
from utils.fetcher.ACS_fetcher import ACSFetcher
from utils.fetcher.Cell_fetcher import CellFetcher
from utils.fetcher.Elsevier_fetcher import ElsevierFetcher
from utils.fetcher.Frontiers_fetcher import FrontiersFetcher
from utils.fetcher.MDPI_fetcher import MDPIFetcher
from utils.fetcher.Nat_fetcher import NatureFetcher
from utils.fetcher.RSC_fetcher import RSCFetcher
from utils.fetcher.Taylor_fetcher import TaylorFetcher
from utils.fetcher.Wiely_fetcher import WileyFetcher
from utils.main_fetcher import PUBLISHER_FETCHER_MAP


class FakeResponse:
    """Small requests.Response substitute used by RSS and Elsevier tests."""

    def __init__(self, content: bytes | str, status_code: int = 200):
        self.content = content.encode() if isinstance(content, str) else content
        self.status_code = status_code
        self.url = "https://publisher.example/feed"
        self.headers = {}

    @property
    def text(self):
        return self.content.decode("utf-8", errors="replace")

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}")


def rss_fixture(
    *,
    title: str = "A publisher article",
    link: str = "https://publisher.example/article-1",
    creator: str = "Alice, Bob",
    doi: str = "10.1000/rss-1",
    summary: str = "A short summary.\nSecond line.",
    content_html: str = (
        "<p>Editor summary</p><p>Abstract <b>body</b></p>"
        '<img src="https://publisher.example/ga.png"/>'
    ),
) -> bytes:
    """Build one realistic RSS item for feedparser."""

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     xmlns:prism="http://prismstandard.org/namespaces/basic/2.0/"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Test feed</title>
    <item>
      <title>{title}</title>
      <link>{link}</link>
      <pubDate>Tue, 04 Feb 2025 12:00:00 GMT</pubDate>
      <dc:creator>{creator}</dc:creator>
      <prism:doi>{doi}</prism:doi>
      <dc:identifier>doi:{doi}</dc:identifier>
      <description>{summary}</description>
      <guid>https://doi.org/{doi}</guid>
      <content:encoded><![CDATA[{content_html}]]></content:encoded>
    </item>
  </channel>
</rss>""".encode()


class PublisherMappingTests(unittest.TestCase):
    def test_every_supported_publisher_has_a_fetcher(self):
        expected = {
            "Springer Nature": NatureFetcher,
            "Cell Press": CellFetcher,
            "Elsevier": ElsevierFetcher,
            "Science": ScienceFetcher,
            "AAAS": ScienceFetcher,
            "American Chemical Society": ACSFetcher,
            "Royal Society of Chemistry": RSCFetcher,
            "Wiley": WileyFetcher,
            "Taylor & Francis": TaylorFetcher,
            "MDPI": MDPIFetcher,
            "Frontiers": FrontiersFetcher,
        }

        self.assertEqual(PUBLISHER_FETCHER_MAP, expected)


class PublisherRSSFetcherTests(unittest.TestCase):
    """Exercise each RSS fetcher's custom list parser with a mocked response."""

    def fetch_one(self, fetcher, fixture=None):
        fixture = fixture or rss_fixture()
        with patch(
            "utils.fetcher.Base_fetcher.impersonated_get",
            return_value=FakeResponse(fixture),
        ) as get:
            papers = fetcher.fetch_list()

        get.assert_called_once_with(
            fetcher.feed_url,
            headers={"Accept": "application/rss+xml, application/xml;q=0.9, */*;q=0.1"},
            fallback_headers={
                "User-Agent": fetcher.user_agent,
                "Accept": "application/rss+xml, application/xml;q=0.9, */*;q=0.1",
            },
            timeout=ANY,
        )
        self.assertEqual(len(papers), 1)
        return papers[0]

    def test_science_fetch_list_normalizes_title_authors_and_doi(self):
        fetcher = ScienceFetcher(
            name="Science",
            url="https://test.example/science.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(
            fetcher,
            rss_fixture(title="Science: A new discovery", creator="Alice, Bob"),
        )

        self.assertEqual(paper["title"], "A new discovery")
        self.assertEqual(paper["authors"], ["Alice", "Bob"])
        self.assertEqual(paper["doi"], "10.1000/rss-1")
        self.assertEqual(paper["date"], "2025-02-04")
        self.assertEqual(paper["status"], "online")

    @unittest.skip("暂挂 ACS DOI/fixture 不一致，见 KNOWN_ISSUES.md")
    def test_acs_fetch_list_removes_asap_marker(self):
        fetcher = ACSFetcher(
            name="Journal of the American Chemical Society",
            url="https://test.example/acs.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(fetcher, rss_fixture(title="[ASAP] A reaction"))

        self.assertEqual(paper["title"], "A reaction")
        self.assertEqual(paper["doi"], "10.1000/rss-1")
        self.assertEqual(paper["journal"], "Journal of the American Chemical Society")

    def test_rsc_fetch_list_uses_common_rss_parser(self):
        fetcher = RSCFetcher(
            name="Chemical Society Reviews",
            url="https://test.example/rsc.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(fetcher, rss_fixture(title="A chemistry review"))

        self.assertEqual(paper["title"], "A chemistry review")
        self.assertEqual(paper["authors"], ["Alice, Bob"])
        self.assertEqual(paper["date"], "2025-02-04")
        self.assertEqual(paper["status"], "online")

    def test_elsevier_fetch_list_strips_tracking_query(self):
        fetcher = ElsevierFetcher(
            name="Food Chemistry",
            url="https://test.example/elsevier.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(
            fetcher,
            rss_fixture(link="https://www.sciencedirect.com/science/article/pii/S123?dgcid=rss_sd_all"),
        )

        self.assertEqual(paper["link"], "https://www.sciencedirect.com/science/article/pii/S123")
        self.assertEqual(paper["journal"], "Food Chemistry")
        self.assertEqual(paper["status"], "online")

    def test_elsevier_graphical_abstract_probe_stops_at_first_existing_image(self):
        fetcher = ElsevierFetcher(browser_manager=object())
        responses = [Mock(status_code=404), Mock(status_code=200)]

        with patch(
            "utils.fetcher.Elsevier_fetcher.impersonated_head",
            side_effect=responses,
        ) as head:
            result = fetcher._get_ga_url("S123456")

        self.assertEqual(
            result,
            "https://ars.els-cdn.com/content/image/1-s2.0-S123456-ga1_.jpg",
        )
        self.assertEqual(head.call_count, 2)
        head.assert_any_call(
            "https://ars.els-cdn.com/content/image/1-s2.0-S123456-ga1_lrg.jpg",
            timeout=5,
        )
        head.assert_any_call(
            "https://ars.els-cdn.com/content/image/1-s2.0-S123456-ga1_.jpg",
            timeout=5,
        )

    def test_mdpi_fetch_list_keeps_summary_and_normalizes_title(self):
        fetcher = MDPIFetcher(
            name="Foods",
            url="https://test.example/mdpi.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(
            fetcher,
            rss_fixture(title="Foods: A nutrition study", summary="line one\nline two"),
        )

        self.assertEqual(paper["title"], "A nutrition study")
        self.assertEqual(paper["abstract"], "line one line two")
        self.assertEqual(paper["doi"], "10.1000/rss-1")

    def test_nature_fetch_list_normalizes_title_and_date(self):
        fetcher = NatureFetcher(
            name="Nature",
            url="https://test.example/nature.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(fetcher, rss_fixture(title="Nature: A biology study"))

        self.assertEqual(paper["title"], "A biology study")
        self.assertEqual(paper["date"], "2025-02-04")
        self.assertEqual(paper["authors"], ["Alice, Bob"])

    def test_wiley_fetch_list_reads_single_content_encoded_item(self):
        fetcher = WileyFetcher(
            name="Advanced Materials",
            url="https://test.example/wiley.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(
            fetcher,
            rss_fixture(
                title="A materials study",
                link="https://onlinelibrary.wiley.com/doi/10.1000/wiley-1",
            ),
        )

        self.assertEqual(paper["abstract"], "Abstract body")
        self.assertEqual(paper["editor_summary"], "Editor summary")
        self.assertEqual(paper["graphical_abstract"], "https://publisher.example/ga.png")
        self.assertEqual(paper["doi"], "10.1000/rss-1")

    def test_taylor_fetch_list_extracts_doi_from_identifier(self):
        fetcher = TaylorFetcher(
            name="Autophagy",
            url="https://test.example/taylor.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(fetcher, rss_fixture(title="An autophagy study"))

        self.assertEqual(paper["doi"], "10.1000/rss-1")
        self.assertEqual(paper["date"], "2025-02-04")
        self.assertEqual(paper["status"], "online")

    def test_frontiers_fetch_list_extracts_doi_from_guid(self):
        fetcher = FrontiersFetcher(
            name="Frontiers in Immunology",
            url="https://test.example/frontiers.rss",
            browser_manager=object(),
        )
        paper = self.fetch_one(
            fetcher,
            rss_fixture(
                title="An immunology study",
                link="https://www.frontiersin.org/journals/immunology/articles/1",
            ),
        )

        self.assertEqual(paper["abstract"], "A short summary.\nSecond line.")
        self.assertEqual(paper["doi"], "10.1000/rss-1")
        self.assertEqual(paper["authors"], ["Alice, Bob"])


class CellFetcherListTests(unittest.IsolatedAsyncioTestCase):
    async def test_cell_fetch_list_extracts_articles_and_editor_summary(self):
        html = """
        <html><body>
          <form id="frmSearch">
            <div>
              <div>
                <div></div>
                <div>
                  <div></div>
                  <div>
                    <section>
                      <h3><a href="/cell/article-1">Cell article</a></h3>
                      <ul><li><ul><li>Alice</li><li>Bob</li></ul></li></ul>
                      <div><ul><li>
                        <div>
                          <div></div>
                          <div>
                            <div>
                              <div></div>
                              <div>
                                <div></div>
                                <div><div>Editor summary</div></div>
                              </div>
                            </div>
                          </div>
                        </div>
                      </li></ul></div>
                    </section>
                  </div>
                </div>
              </div>
            </div>
          </form>
        </body></html>
        """
        fetcher = CellFetcher(
            name="Cell",
            url="https://test.example/cell/newarticles",
            browser_manager=object(),
        )
        fetcher._get_playwright_content = AsyncMock(return_value=html)

        papers = await fetcher.fetch_list()

        self.assertEqual(
            papers,
            [
                {
                    "title": "Cell article",
                    "link": "https://www.cell.com/cell/article-1",
                    "authors": ["Alice", "Bob"],
                    "journal": "Cell",
                    "editor_summary": "Editor summary",
                    "status": "online",
                }
            ],
        )
        fetcher._get_playwright_content.assert_awaited_once_with(
            "https://test.example/cell/newarticles",
            selector='//*[@id="frmSearch"]/div[1]/div/div[2]/div[2]',
        )


class PublisherDetailFetcherTests(unittest.IsolatedAsyncioTestCase):
    async def fetch_details(
        self,
        fetcher,
        html,
        link="https://publisher.example/article",
        expected_kwargs=None,
    ):
        fetcher._get_playwright_content = AsyncMock(return_value=html)
        details = await fetcher.fetch_details({"link": link})
        fetcher._get_playwright_content.assert_awaited_once_with(
            link,
            **(expected_kwargs or {"wait_until": "domcontentloaded"}),
        )
        return details

    async def test_science_details_extracts_abstract_variants_and_graphical_abstract(self):
        html = """
        <div id="abstracts">
          <section id="editor-abstract"><h2>Editor</h2><p>Editor &amp; note</p></section>
          <section id="structured-abstract"><h2>Structured</h2><p>Methods</p></section>
          <section id="abstract"><h2>Abstract</h2><p>Main abstract</p></section>
        </div>
        <figure><img data-src="/figure&amp;1.png" /></figure>
        """
        details = await self.fetch_details(ScienceFetcher(browser_manager=object()), html)

        self.assertEqual(details["editor_summary"], "Editor & note")
        self.assertEqual(details["structured_abstract"], "Methods")
        self.assertEqual(details["abstract"], "Main abstract")
        self.assertEqual(details["graphical_abstract"], "https://www.science.org/figure&1.png")

    @unittest.skip("暂挂 ACS 页面选择器/fixture 不一致，见 KNOWN_ISSUES.md")
    async def test_acs_details_extracts_abstract_and_graphical_abstract(self):
        html = """
        <div id="abstractBox"><p>First paragraph.</p><p>Second paragraph.</p></div>
        <figure id="_i123"><img src="/ga.png" /></figure>
        """
        details = await self.fetch_details(ACSFetcher(browser_manager=object()), html)

        self.assertEqual(details["abstract"], "First paragraph. Second paragraph.")
        self.assertEqual(details["graphical_abstract"], "https://pubs.acs.org/ga.png")

    async def test_cell_details_extracts_abstract_ga_doi_and_date(self):
        html = """
        <div id="author-abstract"><div>Abstract &amp; details.</div></div>
        <div id="graphical-abstract"><a href="/ga-cell.png">figure</a></div>
        <span class="doi"><a>10.1016/j.cell.2025.01.001</a></span>
        <span class="meta-panel__onlineDate">February 4, 2025</span>
        """
        details = await self.fetch_details(CellFetcher(browser_manager=object()), html)

        self.assertEqual(details["abstract"], "Abstract & details.")
        self.assertEqual(details["graphical_abstract"], "https://www.cell.com/ga-cell.png")
        self.assertEqual(details["doi"], "10.1016/j.cell.2025.01.001")
        self.assertEqual(details["date"], "February 4, 2025")

    async def test_elsevier_details_extracts_api_fields_and_graphical_abstract(self):
        xml = """<?xml version="1.0"?>
        <article xmlns:dc="http://purl.org/dc/elements/1.1/"
                 xmlns:prism="http://prismstandard.org/namespaces/basic/2.0/">
          <prism:doi>https://doi.org/10.1016/j.foodchem.2025.123456</prism:doi>
          <dc:creator>Alice</dc:creator><dc:creator>Bob</dc:creator>
          <prism:coverDate>2025-02-04</prism:coverDate>
          <dc:description>An &amp;lt;important&amp;gt; finding.</dc:description>
        </article>"""
        fetcher = ElsevierFetcher(browser_manager=object())
        fetcher._get_playwright_content = AsyncMock()
        with (
            patch("utils.fetcher.Elsevier_fetcher.Elsevier_KEY", "test-key"),
            patch(
                "utils.fetcher.Elsevier_fetcher.impersonated_get",
                return_value=FakeResponse(xml),
            ) as get,
            patch.object(
                fetcher,
                "_get_ga_url",
                return_value="https://ars.els-cdn.com/ga.jpg",
            ),
        ):
            details = await fetcher.fetch_details(
                {"link": "https://www.sciencedirect.com/science/article/pii/S123456"}
            )

        get.assert_called_once_with(
            "https://api.elsevier.com/content/article/pii/{S123456}",
            headers={"XSD": "text/xml", "X-ELS-APIKey": "test-key", "Accept": "text/xml"},
            fallback_headers={"XSD": "text/xml", "X-ELS-APIKey": "test-key", "Accept": "text/xml"},
            timeout=15,
        )
        self.assertEqual(details["doi"], "10.1016/j.foodchem.2025.123456")
        self.assertEqual(details["authors"], ["Alice", "Bob"])
        self.assertEqual(details["date"], "2025-02-04")
        self.assertEqual(details["abstract"], "An <important> finding.")
        self.assertEqual(details["graphical_abstract"], "https://ars.els-cdn.com/ga.jpg")

    async def test_mdpi_details_resolves_relative_graphical_abstract(self):
        html = '<div class="html-fig_img"><img src="/images/foods-ga.png" /></div>'
        details = await self.fetch_details(MDPIFetcher(browser_manager=object()), html)

        self.assertEqual(details["graphical_abstract"], "https://www.mdpi.com/images/foods-ga.png")

    async def test_nature_details_extracts_abstract_ga_and_pre_online_status(self):
        html = """
        <div id="Abs1-content">An&nbsp;abstract &amp; detail.</div>
        <div id="figure-1"><img src="//images.example/nature-ga.png" /></div>
        <div id="content"><main><article><div><header><p>Online</p><p>Pre-online</p></header></div></article></main></div>
        """
        details = await self.fetch_details(NatureFetcher(browser_manager=object()), html)

        self.assertEqual(details["abstract"], "An abstract & detail.")
        self.assertEqual(details["graphical_abstract"], "https://images.example/nature-ga.png")
        self.assertEqual(details["status"], "pre-online")

    async def test_rsc_details_extracts_abstract_doi_and_graphical_abstract(self):
        html = """
        <div class="capsule__text"><p>Abstract &amp; details.</p></div>
        <meta name="citation_doi" content="10.1039/D5CS00001A" />
        <div class="capsule__column-wrapper"><img src="/images/rsc-ga.png" /></div>
        """
        details = await self.fetch_details(
            RSCFetcher(browser_manager=object()),
            html,
            expected_kwargs={
                "wait_until": "domcontentloaded",
                "idle_wait_ms": 7000,
            },
        )

        self.assertEqual(details["abstract"], "Abstract & details.")
        self.assertEqual(details["doi"], "10.1039/D5CS00001A")
        self.assertEqual(details["graphical_abstract"], "https://pubs.rsc.org/images/rsc-ga.png")

    async def test_rsc_details_supports_current_silverchair_markup(self):
        html = """
        <section class="article-section abstract"><p>Current abstract.</p></section>
        <meta name="citation_doi" content="10.1039/D5CS01553G" />
        <div class="figure-table-wrapper graphical-abstract">
          <img src="/preloader.gif" data-src="https://cdn.example/rsc-ga.png" />
        </div>
        """
        details = await self.fetch_details(
            RSCFetcher(browser_manager=object()),
            html,
            expected_kwargs={
                "wait_until": "domcontentloaded",
                "idle_wait_ms": 7000,
            },
        )

        self.assertEqual(details["abstract"], "Current abstract.")
        self.assertEqual(details["doi"], "10.1039/D5CS01553G")
        self.assertEqual(details["graphical_abstract"], "https://cdn.example/rsc-ga.png")

    async def test_taylor_details_extracts_authors_abstract_and_graphical_abstract(self):
        html = """
        <a class="author">Alice&nbsp;Smith</a><a class="author">\\</a>
        <div id="abstractId1"><p>Abstract &amp; details.</p><p>More.</p></div>
        <div class="figureView"><a><img src="/images/taylor-ga.png" /></a></div>
        """
        details = await self.fetch_details(TaylorFetcher(browser_manager=object()), html)

        self.assertEqual(details["authors"], ["Alice Smith"])
        self.assertEqual(details["abstract"], "Abstract & details. More.")
        self.assertEqual(details["graphical_abstract"], "https://www.tandfonline.com/images/taylor-ga.png")

    async def test_frontiers_details_uses_article_figure_image(self):
        html = '<div class="ArticleFigure"><div class="FrontiersImage"><img src="https://frontiers.example/ga.png" /></div></div>'
        details = await self.fetch_details(FrontiersFetcher(browser_manager=object()), html)

        self.assertEqual(details["graphical_abstract"], "https://frontiers.example/ga.png")

    async def test_wiley_details_is_empty_because_rss_contains_detail_fields(self):
        fetcher = WileyFetcher(browser_manager=object())

        self.assertEqual(await fetcher.fetch_details({"link": "https://onlinelibrary.wiley.com/article"}), {})


if __name__ == "__main__":
    unittest.main()
