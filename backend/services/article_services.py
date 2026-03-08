import logging
import json
from typing import Optional, List, Union, TypedDict

from sqlalchemy import text
from db.database import get_db_connection

logger = logging.getLogger(__name__)


class Article(TypedDict):
    title: str
    link: str
    doi: Optional[str]
    date: Optional[str]
    journal: Optional[str]
    authors: list[str]
    editor_summary: Optional[str]
    structured_abstract: Optional[str]
    abstract: Optional[str]
    graphical_abstract: Optional[str]
    status: str


class ArticleService:
    def article_filter(self, articles: List[dict]) -> List[dict]:
        if not articles:
            return []

        titles = [a.get("title") for a in articles if a.get("title")]
        links = [a.get("link") for a in articles if a.get("link")]
        dois = [a.get("doi") for a in articles if a.get("doi")]

        existing_titles: set[str] = set()
        existing_links: set[str] = set()
        existing_dois: set[str] = set()

        with get_db_connection() as conn:
            if titles:
                existing_titles.update(
                    conn.execute(text("SELECT title FROM articles WHERE title = ANY(:v)"), {"v": titles}).scalars().all()
                )
                existing_titles.update(
                    conn.execute(text("SELECT title FROM non_article_entries WHERE title = ANY(:v)"), {"v": titles}).scalars().all()
                )

            if links:
                existing_links.update(
                    conn.execute(text("SELECT link FROM articles WHERE link = ANY(:v)"), {"v": links}).scalars().all()
                )
                existing_links.update(
                    conn.execute(text("SELECT link FROM non_article_entries WHERE link = ANY(:v)"), {"v": links}).scalars().all()
                )

            if dois:
                existing_dois.update(
                    conn.execute(text("SELECT doi FROM articles WHERE doi = ANY(:v)"), {"v": dois}).scalars().all()
                )
                existing_dois.update(
                    conn.execute(text("SELECT doi FROM non_article_entries WHERE doi = ANY(:v)"), {"v": dois}).scalars().all()
                )

        new_articles = []
        for article in articles:
            title = article.get("title")
            link = article.get("link")
            doi = article.get("doi")

            if (doi and doi in existing_dois) or (title and title in existing_titles) or (link and link in existing_links):
                continue
            new_articles.append(article)

        return new_articles

    def insert_articles(self, articles: Union[List[dict], str]):
        if not articles:
            return

        if isinstance(articles, str):
            try:
                articles = json.loads(articles)
            except json.JSONDecodeError as e:
                logger.error("Error decoding JSON in insert_articles: %s", e)
                return

        with get_db_connection() as conn:
            journal_names = list({a.get("journal") for a in articles if a.get("journal")})
            journal_map: dict[str, int] = {}

            if journal_names:
                rows = conn.execute(
                    text("SELECT name, id FROM journals WHERE name = ANY(:names)"),
                    {"names": journal_names},
                ).mappings().all()
                journal_map = {r["name"]: int(r["id"]) for r in rows}

            data_to_insert: list[dict] = []
            non_article_rows: list[dict] = []

            for a in articles:
                title = a.get("title")
                link = a.get("link")
                abstract = a.get("abstract")
                fetch_status = a.get("_fetch_status", "unknown")
                fetch_fail_reason = a.get("_fetch_fail_reason")
                journal_id = journal_map.get(a.get("journal") or "")

                if not title or not link:
                    continue

                if not abstract:
                    if fetch_status != "ok":
                        logger.warning(
                            "Skip non-article classification due fetch status: title=%s, status=%s, reason=%s",
                            title,
                            fetch_status,
                            fetch_fail_reason,
                        )
                        continue

                    if journal_id is None:
                        continue

                    non_article_rows.append(
                        {
                            "title": title,
                            "link": link,
                            "date": a.get("date"),
                            "journal_id": journal_id,
                            "doi": a.get("doi"),
                        }
                    )
                    continue

                authors_json = json.dumps(a.get("authors", []), ensure_ascii=False)

                data_to_insert.append(
                    {
                        "title": title,
                        "link": link,
                        "doi": a.get("doi"),
                        "date": a.get("date"),
                        "journal_id": journal_id,
                        "authors": authors_json,
                        "editor_summary": a.get("editor_summary"),
                        "structured_abstract": a.get("structured_abstract"),
                        "abstract": a.get("abstract"),
                        "graphical_abstract": a.get("graphical_abstract"),
                        "status": a.get("status", "pending"),
                    }
                )

            if data_to_insert:
                conn.execute(
                    text(
                        """
                        INSERT INTO articles (
                          title, link, doi, date, journal_id, authors,
                          editor_summary, structured_abstract, abstract, graphical_abstract, status
                        )
                        VALUES (
                          :title, :link, :doi, :date, :journal_id, :authors,
                          :editor_summary, :structured_abstract, :abstract, :graphical_abstract, :status
                        )
                        ON CONFLICT DO NOTHING
                        """
                    ),
                    data_to_insert,
                )

            if non_article_rows:
                conn.execute(
                    text(
                        """
                        INSERT INTO non_article_entries (title, link, date, journal_id, doi)
                        VALUES (:title, :link, :date, :journal_id, :doi)
                        ON CONFLICT DO NOTHING
                        """
                    ),
                    non_article_rows,
                )

    def insert_non_article_entry(self, entry: dict):
        if not entry.get("title") or not entry.get("link") or entry.get("journal_id") is None:
            return

        with get_db_connection() as conn:
            conn.execute(
                text(
                    """
                    INSERT INTO non_article_entries (title, link, date, journal_id, doi)
                    VALUES (:title, :link, :date, :journal_id, :doi)
                    ON CONFLICT DO NOTHING
                    """
                ),
                {
                    "title": entry.get("title"),
                    "link": entry.get("link"),
                    "date": entry.get("date"),
                    "journal_id": entry.get("journal_id"),
                    "doi": entry.get("doi"),
                },
            )