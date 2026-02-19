from db.database import get_db_connection

class ArticleRepository:
    def get_pending_articles(self, limit=None):
        """获取等待处理的文章"""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            if limit is not None:
                cursor.execute(
                    "SELECT id, abstract, editor_summary, structured_abstract FROM articles WHERE llm_summary IS NULL AND llm_status IS NULL LIMIT ?",
                    (limit,)
                )
            else:
                cursor.execute(
                    "SELECT id, abstract, editor_summary, structured_abstract FROM articles WHERE llm_summary IS NULL AND llm_status IS NULL"
                )
            rows = cursor.fetchall()
            ids = [row['id'] for row in rows]
            return rows, ids

    def mark_articles_as_submitted(self, article_ids, batch_id):
        """标记文章为已提交状态"""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.executemany(
                "UPDATE articles SET llm_status = ? WHERE id = ?",
                [(batch_id, aid) for aid in article_ids]
            )
            conn.commit()

    def clear_article_llm_status(self, article_id):
        """清除文章的 LLM 状态（用于重试）"""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "UPDATE articles SET llm_status = NULL , llm_summary = NULL WHERE id = ?",
                (article_id,)
            )
            conn.commit()

    def update_article_summaries(self, updates):
        """批量更新文章摘要和状态"""
        # updates = [(summary, status, id), ...]
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.executemany(
                """
                UPDATE articles 
                SET llm_summary = ?, processed_at = CURRENT_TIMESTAMP, llm_status = ? 
                WHERE id = ?
                """,
                updates
            )
            conn.commit()

    def get_active_batch_ids(self):
        """获取所有未完成的 batch id"""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT DISTINCT llm_status FROM articles WHERE llm_summary IS NULL AND llm_status IS NOT NULL AND llm_status != 'processed'"
            )
            return [row['llm_status'] for row in cursor.fetchall()]