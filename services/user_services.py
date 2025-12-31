import sqlite3
from database import get_db_connection
from utils.auth import hash_password, verify_password

class UserService:
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
            return dict(user)

    def follow_journal(self, user_id: int, journal_id: int) -> bool:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            try:
                cursor.execute(
                    "INSERT INTO user_journal_subscriptions (user_id, journal_id) VALUES (?, ?)",
                    (user_id, journal_id)
                )
                return True
            except sqlite3.IntegrityError:
                return False  # 已关注

    def unfollow_journal(self, user_id: int, journal_id: int) -> bool:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "DELETE FROM user_journal_subscriptions WHERE user_id = ? AND journal_id = ?",
                (user_id, journal_id)
            )
            return cursor.rowcount > 0
        
    def get_articles_feed(self, user_id: int, limit: int = 200, offset: int = 0) -> list:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT 
                    a.id, a.title, a.abstract, a.date, a.journal_name,
                    CASE WHEN uar.article_id IS NOT NULL THEN 1 ELSE 0 END as is_read
                FROM articles a
                JOIN user_journal_subscriptions ujs ON a.journal_name = (SELECT name FROM journals WHERE id = ujs.journal_id)
                LEFT JOIN user_article_reads uar ON a.id = uar.article_id AND uar.user_id = ?
                WHERE ujs.user_id = ?
                ORDER BY a.date DESC
                LIMIT ? OFFSET ?
                """,
                (user_id, user_id, limit, offset)
            )
            articles = cursor.fetchall()
            return [dict(article) for article in articles]

    def mark_as_read(self, user_id: int, article_ids: list):
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.executemany(
                "INSERT OR IGNORE INTO user_article_reads (user_id, article_id) VALUES (?, ?)",
                [(user_id, aid) for aid in article_ids]
            )
