from sqlalchemy import text
from db.database import get_db_connection


class ArticleRepository:
    def get_pending_articles(self, limit: int | None = None) -> tuple[list[dict], list[int]]:
        with get_db_connection() as conn:
            if limit is not None:
                rows = conn.execute(
                    text(
                        """
                        SELECT id, abstract, editor_summary, structured_abstract
                        FROM articles
                        WHERE llm_summary IS NULL AND llm_status IS NULL
                        LIMIT :limit
                        """
                    ),
                    {"limit": limit},
                ).mappings().all()
            else:
                rows = conn.execute(
                    text(
                        """
                        SELECT id, abstract, editor_summary, structured_abstract
                        FROM articles
                        WHERE llm_summary IS NULL AND llm_status IS NULL
                        """
                    )
                ).mappings().all()

            rows = [dict(r) for r in rows]
            ids = [r["id"] for r in rows]
            return rows, ids

    def mark_articles_as_submitted(self, article_ids: list[int], batch_id: str) -> None:
        with get_db_connection() as conn:
            conn.execute(
                text("UPDATE articles SET llm_status = :batch WHERE id = :id"),
                [{"batch": batch_id, "id": int(aid)} for aid in article_ids],
            )

    def clear_article_llm_status(self, article_id: int) -> None:
        with get_db_connection() as conn:
            conn.execute(
                text(
                    "UPDATE articles SET llm_status = NULL, llm_summary = NULL WHERE id = :id"),
                {"id": int(article_id)},
            )

    def clear_batch_llm_status(self, batch_id:str) -> None:
        with get_db_connection() as conn:
            conn.execute(
                text(
                    "UPDATE articles SET llm_status = NULL, llm_summary = NULL WHERE llm_status = :b"),
                {"b": batch_id},
            )

    def update_article_summaries(self, updates: list[tuple[str, str, int]]) -> None:
        # updates = [(summary, status, id), ...]
        payload = [{"summary": s, "status": st,
                    "id": int(i)} for (s, st, i) in updates]
        with get_db_connection() as conn:
            conn.execute(
                text(
                    """
                    UPDATE articles
                    SET llm_summary = :summary,
                        processed_at = now(),
                        llm_status = :status
                    WHERE id = :id
                    """
                ),
                payload,
            )

    def get_active_batch_ids(self) -> list[str]:
        with get_db_connection() as conn:
            ids = conn.execute(
                text(
                    """
                    SELECT DISTINCT llm_status
                    FROM articles
                    WHERE llm_summary IS NULL
                      AND llm_status IS NOT NULL
                      AND llm_status != 'processed'
                    """
                )
            ).scalars().all()
            return list(ids)
