import sqlite3
from db.database import get_db_connection
from utils.auth import hash_password, verify_password

class UserService:
    def get_user_by_id(self, user_id: int) -> dict | None:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, username, email FROM users WHERE id = ?",
                (user_id,)
            )
            user = cursor.fetchone()
            if user:
                return {
                    "id": user["id"],
                    "username": user["username"],
                    "email": user["email"],
                }
            return None


    def register(self, username: str, email: str, password: str) -> dict:
        hashed_pw = hash_password(password)
        
        with get_db_connection() as conn:
            cursor = conn.cursor()
            try:
                cursor.execute(
                    "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)",
                    (username, email, hashed_pw)
                )
                user_id = cursor.lastrowid
                return {"id": user_id, "username": username, "email": email}
            except sqlite3.IntegrityError as e:
                if "username" in str(e):
                    raise ValueError("Username already exists")
                if "email" in str(e):
                    raise ValueError("Email already registered")
                raise e

    def login(self, username: str, password: str) -> dict:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, username, email, password_hash FROM users WHERE username = ?",
                (username,)
            )
            user = cursor.fetchone()
            if not user or not verify_password(password, user["password_hash"]):
                raise ValueError("Invalid credentials")
            return {
                "id": user["id"],
                "username": user["username"],
                "email": user["email"],
            }

        
    def get_available_journals(self, limit: int = 50, offset: int = 0) -> list[dict]:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT id, name, sci, if, if5, CASUp, CASBase, publisher, abbreviation FROM journals WHERE official_url IS NOT NULL OR rss_url IS NOT NULL LIMIT ? OFFSET ?", 
                (limit, offset))
            journals = cursor.fetchall()
            return [dict(journal) for journal in journals]

    def get_followed_journals(self, user_id: int) -> list[int]:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT j.id
                FROM journals j
                JOIN user_journal_subscriptions ujs ON j.id = ujs.journal_id
                WHERE ujs.user_id = ?
                """,
                (user_id,)
            )
            rows = cursor.fetchall()
            return [int(r[0]) for r in rows]

    def follow_journal(self, user_id: int, journal_id: int) -> bool:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            try:
                # 1. 插入订阅记录
                cursor.execute(
                    "INSERT INTO user_journal_subscriptions (user_id, journal_id) VALUES (?, ?)",
                    (user_id, journal_id)
                )
                
                # 2. 激活该期刊的爬虫开关
                cursor.execute(
                    "UPDATE journals SET crawler_enabled = 1 WHERE id = ?",
                    (journal_id,)
                )
                conn.commit()
                return True
            except sqlite3.IntegrityError as e:
                if "FOREIGN KEY constraint failed" in str(e):
                    raise ValueError("Journal not found")
                return False  # 已关注

    def unfollow_journal(self, user_id: int, journal_id: int) -> bool:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            # 1. 删除订阅记录
            cursor.execute(
                "DELETE FROM user_journal_subscriptions WHERE user_id = ? AND journal_id = ?",
                (user_id, journal_id)
            )
            
            if cursor.rowcount > 0:
                # 2. 检查是否还有其他用户订阅该期刊
                cursor.execute(
                    "SELECT COUNT(*) FROM user_journal_subscriptions WHERE journal_id = ?",
                    (journal_id,)
                )
                count = cursor.fetchone()[0]
                
                # 3. 如果没人订阅了，关闭爬虫开关
                if count == 0:
                    cursor.execute(
                        "UPDATE journals SET crawler_enabled = 0 WHERE id = ?",
                        (journal_id,)
                    )
                return True
            return False
        
    def get_articles_feed(self, user_id: int, limit: int = 200, offset: int = 0) -> list[dict]:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                a.id,
                a.title,
                a.abstract,
                a.graphical_abstract,
                a.date,
                a.doi,
                a.llm_summary,
                j.id   AS journal_id,
                j.name AS journal_name,
                j.abbreviation
                FROM articles a
                JOIN journals j ON a.journal_id = j.id
                JOIN user_journal_subscriptions ujs
                ON ujs.journal_id = j.id
                WHERE ujs.user_id = ? AND a.llm_summary IS NOT NULL
                ORDER BY a.id DESC
                LIMIT ? OFFSET ?
                """,
                (user_id, limit, offset)
            )
            articles = cursor.fetchall()
            return [dict(article) for article in articles]
        
    def get_article_by_id(self, article_id: int) -> dict | None:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                a.id,
                a.title,
                a.abstract,
                a.graphical_abstract,
                a.date,
                a.doi,
                a.llm_summary,
                j.id   AS journal_id,
                j.name AS journal_name,
                j.abbreviation
                FROM articles a
                JOIN journals j ON a.journal_id = j.id
                WHERE a.id = ?
                """,
                (article_id,)
            )
            article = cursor.fetchone()
            if article:
                return dict(article)
            return None

    def mark_as_read(self, user_id: int, article_ids: list[int]) -> bool:
        if not article_ids:
            return True
        with get_db_connection() as conn:
            cursor = conn.cursor()
            try:
                # 为了区分“文章不存在”和“重复标记”，我们不再使用 INSERT OR IGNORE
                # 而是分两步：1. 检查所有文章 ID 是否有效（外键约束也会在写入时检查）
                # 2. 执行批量插入
                
                # 检查这些文章是否存在
                placeholders = ', '.join(['?'] * len(article_ids))
                cursor.execute(f"SELECT COUNT(*) FROM articles WHERE id IN ({placeholders})", article_ids)
                if cursor.fetchone()[0] < len(set(article_ids)):
                    raise ValueError("One or more article IDs do not exist")

                cursor.executemany(
                    "INSERT OR IGNORE INTO user_article_reads (user_id, article_id) VALUES (?, ?)",
                    [(user_id, aid) for aid in article_ids]
                )
                conn.commit()
                return True
            except sqlite3.IntegrityError as e:
                # 虽然用了 OR IGNORE，但如果外键检查生效且失败，依然可能抛出异常
                if "FOREIGN KEY constraint failed" in str(e):
                    raise ValueError("One or more article IDs or User ID do not exist")
                return False
            
    def add_favorite(self, user_id: int, article_id: int) -> bool:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            try:
                cursor.execute(
                    "INSERT INTO user_article_favourites (user_id, article_id) VALUES (?, ?)",
                    (user_id, article_id)
                )
                conn.commit()
                return True
            except sqlite3.IntegrityError as e:
                if "FOREIGN KEY constraint failed" in str(e):
                    # 区分：文章不存在
                    raise ValueError("Article not found")
                return False  # 已收藏
            
    def del_favorite(self, user_id: int, article_id: int) -> bool:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "DELETE FROM user_article_favourites WHERE user_id = ? AND article_id = ?",
                (user_id, article_id)
            )
            conn.commit()
            return cursor.rowcount > 0
        
    def get_favorite_articles(self, user_id: int) -> list[int]:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT article_id
                FROM user_article_favourites
                WHERE user_id = ?
                """,
                (user_id,)
            )
            rows = cursor.fetchall()
            return [int(r[0]) for r in rows]
        
    def get_read_articles(self, user_id: int) -> list[int]:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT article_id
                FROM user_article_reads
                WHERE user_id = ?
                """,
                (user_id,)
            )
            rows = cursor.fetchall()
            return [int(r[0]) for r in rows]