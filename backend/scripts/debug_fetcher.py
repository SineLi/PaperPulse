"""Debug a single publisher fetcher without touching PostgreSQL.

The default flow never calls ``collect()``/``run()``/``finalize()``, so no
database connection is opened: the script only exercises the RSS/list fetch
and the per-article detail fetch through a private, small browser pool.

Examples:
  python scripts/debug_fetcher.py nature
  python scripts/debug_fetcher.py mdpi --detail --limit 2
  python scripts/debug_fetcher.py acs --url "https://pubs.acs.org/doi/10.1021/jacs.5xxxxxx"
  python scripts/debug_fetcher.py nature --url "..." --html-dir tmp/html
  python scripts/debug_fetcher.py nature --insert   # opt-in: also filter + write to DB

Elsevier details additionally require ``Elsevier_KEY`` in the environment.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

load_dotenv(BACKEND_DIR / ".env")

from utils.browser_manager import BrowserManager  # noqa: E402
from utils.main_fetcher import PUBLISHER_FETCHER_MAP  # noqa: E402


LOGGER = logging.getLogger("debug_fetcher")

# 常用别名，避免每次都要输入完整的出版商名
ALIASES = {
    "nature": "Springer Nature",
    "springer": "Springer Nature",
    "cell": "Cell Press",
    "science": "Science",
    "aaas": "AAAS",
}


def resolve_fetcher_cls(name: str):
    needle = name.strip().lower()
    aliases = {key.lower(): value.lower() for key, value in ALIASES.items()}
    if needle in aliases:
        needle = aliases[needle]
    matches = {
        key: cls
        for key, cls in PUBLISHER_FETCHER_MAP.items()
        if needle in key.lower() or needle in cls.__name__.lower()
    }
    if not matches:
        raise SystemExit(
            f"no fetcher matches {name!r}; known publishers: {', '.join(sorted(PUBLISHER_FETCHER_MAP))}"
        )
    if len(matches) > 1:
        raise SystemExit(
            f"{name!r} is ambiguous: {', '.join(sorted(matches))}; be more specific"
        )
    key, cls = next(iter(matches.items()))
    return key, cls


def print_articles(papers: list[dict]) -> None:
    if not papers:
        print("(no articles parsed from the list source)")
        return
    for idx, paper in enumerate(papers):
        date = paper.get("date") or "----"
        title = (paper.get("title") or "<no title>")[:80]
        doi = paper.get("doi") or "-"
        print(f"[{idx}] {date}  {title}")
        print(f"     doi={doi}  link={paper.get('link', '')}")


def print_paper(paper: dict) -> None:
    print(json.dumps(paper, ensure_ascii=False, indent=2, default=str))


async def run(args: argparse.Namespace) -> None:
    publisher, fetcher_cls = resolve_fetcher_cls(args.publisher)
    print(f"publisher={publisher} fetcher={fetcher_cls.__name__}")

    browser_manager = BrowserManager(args.pool_size, args.max_pages)
    kwargs: dict[str, Any] = {"browser_manager": browser_manager}
    if args.list_url:
        kwargs["url"] = args.list_url
    if args.user_agent:
        kwargs["user_agent"] = args.user_agent
    fetcher = fetcher_cls(**kwargs)

    try:
        if args.url:
            # 单 URL 模式：不请求列表，直接抓这一篇
            article = {"title": args.url, "link": args.url}
            if args.html_dir:
                await dump_html(fetcher, article, args.html_dir, suffix="single")
            await fetcher.fetch_detail_at_index([article], 0)
            print_paper(article)
            return

        papers = await fetcher._fetch_list()
        print(f"list fetch completed: {len(papers)} articles")
        print_articles(papers[: args.limit])
        if not args.detail and not args.insert:
            return

        targets = papers[: args.limit]
        if not targets:
            return

        for idx in range(len(targets)):
            # 复用生产路径：detail_at_index 会把 _fetch_status/_fetch_fail_reason 写回 article
            await fetcher.fetch_detail_at_index(targets, idx)
            if args.html_dir:
                await dump_html(fetcher, targets[idx], args.html_dir, suffix=str(idx))
            print_paper(targets[idx])

        if args.insert:
            papers_to_insert = await asyncio.to_thread(fetcher.service.article_filter, targets)
            print(f"article_filter kept {len(papers_to_insert)}/{len(targets)} articles")
            await fetcher.finalize(papers_to_insert)
            print("finalize completed: dates normalized and rows inserted")
    finally:
        await browser_manager.close_all_browsers()


async def dump_html(fetcher, article: dict, html_dir: str, suffix: str) -> None:
    """额外发起一次 Playwright 抓取，把服务端真实返回的原始 HTML 落盘。

    与 --url/--detail 的详情抓取是两次独立请求，便于观察挑战页/拦截页内容。
    """
    link = article.get("link", "")
    if not link:
        return
    out_dir = Path(html_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    content = await fetcher._get_playwright_content(link)
    meta = fetcher._pop_fetch_meta(link) or {}
    out_file = out_dir / f"{fetcher.journal_name}_{suffix}.html"
    out_file.write_text(content, encoding="utf-8")
    print(
        f"html dumped: {out_file} ({len(content)} bytes, "
        f"status={meta.get('status')}, reason={meta.get('reason')})"
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("publisher", help="publisher name or alias (nature/cell/science/acs/rsc/wiley/taylor/mdpi/frontiers/elsevier)")
    parser.add_argument("--list-url", help="override the feed/list URL for this run")
    parser.add_argument("--url", help="debug a single article link; skips the list fetch entirely")
    parser.add_argument("--detail", action="store_true", help="also fetch article details for the first --limit list items")
    parser.add_argument("--limit", type=int, default=10, help="how many list items to show/inspect (default 10)")
    parser.add_argument("--html-dir", help="directory to additionally dump raw page HTML into (extra fetch per target)")
    parser.add_argument("--insert", action="store_true", help="opt-in: run article_filter + finalize against the database (needs DATABASE_URL)")
    parser.add_argument("--pool-size", type=int, default=1, help="browser pool size for this debug run (default 1)")
    parser.add_argument("--max-pages", type=int, default=1, help="max pages per browser for this debug run (default 1)")
    parser.add_argument("--user-agent", help="override the fetcher user agent")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING"], help="logging verbosity (default INFO)")
    args = parser.parse_args(argv)
    if args.limit < 1:
        parser.error("--limit must be >= 1")
    return args


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
