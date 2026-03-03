from sqlalchemy import text
from db.database import get_db_connection
from utils.auth import hash_password, verify_password


class UserService:
    def get_user_by_id(self, user_id: int) -> dict | None:
        with get_db_connection() as conn:
            row = conn.execute(
                text("SELECT id, username, email FROM users WHERE id = :id"),
                {"id": user_id},
            ).mappings().first()
            return dict(row) if row else None

    def register(self, username: str, email: str, password: str) -> dict:
        hashed_pw = hash_password(password)

        with get_db_connection() as conn:
            
            if conn.execute(text("SELECT 1 FROM users WHERE username = :u"), {"u": username}).first():
                raise ValueError("Username already exists")
            if conn.execute(text("SELECT 1 FROM users WHERE email = :e"), {"e": email}).first():
                raise ValueError("Email already registered")

            user_id = conn.execute(
                text(
                    """
                    INSERT INTO users (username, email, password_hash)
                    VALUES (:username, :email, :password_hash)
                    RETURNING id
                    """
                ),
                {"username": username, "email": email, "password_hash": hashed_pw},
            ).scalar_one()

            return {"id": int(user_id), "username": username, "email": email}

    def login(self, username: str, password: str) -> dict:
        with get_db_connection() as conn:
            row = conn.execute(
                text("SELECT id, username, email, password_hash FROM users WHERE username = :u"),
                {"u": username},
            ).mappings().first()

            if not row or not verify_password(password, row["password_hash"]):
                raise ValueError("Invalid credentials")

            return {"id": int(row["id"]), "username": row["username"], "email": row["email"]}

    def get_available_journals(self, limit: int = 50, offset: int = 0) -> list[dict]:
        with get_db_connection() as conn:
            rows = conn.execute(
                text(
                    """
                    SELECT
                      id, name, sci, "if", if5, casup, casbase, publisher, abbreviation
                    FROM journals
                    WHERE official_url IS NOT NULL OR rss_url IS NOT NULL
                    ORDER BY id ASC
                    LIMIT :limit OFFSET :offset
                    """
                ),
                {"limit": limit, "offset": offset},
            ).mappings().all()
            return [dict(r) for r in rows]

    def get_followed_journals(self, user_id: int) -> list[int]:
        with get_db_connection() as conn:
            ids = conn.execute(
                text(
                    """
                    SELECT j.id
                    FROM journals j
                    JOIN user_journal_subscriptions ujs ON j.id = ujs.journal_id
                    WHERE ujs.user_id = :uid
                    """
                ),
                {"uid": user_id},
            ).scalars().all()
            return [int(x) for x in ids]

    def follow_journal(self, user_id: int, journal_id: int) -> bool:
        with get_db_connection() as conn:
            # journal 必须存在（用于区分“已关注”和“期刊不存在”）
            if not conn.execute(text("SELECT 1 FROM journals WHERE id = :jid"), {"jid": journal_id}).first():
                raise ValueError("Journal not found")

            inserted = conn.execute(
                text(
                    """
                    INSERT INTO user_journal_subscriptions (user_id, journal_id)
                    VALUES (:uid, :jid)
                    ON CONFLICT DO NOTHING
                    RETURNING id
                    """
                ),
                {"uid": user_id, "jid": journal_id},
            ).scalar()

            if inserted is None:
                return False  # 已关注

            # 只要有用户关注，就启用爬虫
            conn.execute(
                text("UPDATE journals SET crawler_enabled = TRUE WHERE id = :jid"),
                {"jid": journal_id},
            )
            return True

    def unfollow_journal(self, user_id: int, journal_id: int) -> bool:
        with get_db_connection() as conn:
            res = conn.execute(
                text(
                    """
                    DELETE FROM user_journal_subscriptions
                    WHERE user_id = :uid AND journal_id = :jid
                    """
                ),
                {"uid": user_id, "jid": journal_id},
            )

            if (res.rowcount or 0) <= 0:
                return False

            count = conn.execute(
                text("SELECT COUNT(*) FROM user_journal_subscriptions WHERE journal_id = :jid"),
                {"jid": journal_id},
            ).scalar_one()

            if int(count) == 0:
                # 没有用户关注了，禁用爬虫
                conn.execute(
                    text("UPDATE journals SET crawler_enabled = FALSE WHERE id = :jid"),
                    {"jid": journal_id},
                )
            return True

    def get_articles_feed(self, user_id: int, limit: int = 200, offset: int = 0) -> list[dict]:
        with get_db_connection() as conn:
            rows = conn.execute(
                text(
                    """
                    SELECT
                      a.id, a.title, a.abstract, a.graphical_abstract, a.date, a.doi, a.llm_summary,
                      j.id AS journal_id, j.name AS journal_name, j.abbreviation
                    FROM articles a
                    JOIN journals j ON a.journal_id = j.id
                    JOIN user_journal_subscriptions ujs ON ujs.journal_id = j.id
                    WHERE ujs.user_id = :uid AND a.llm_summary IS NOT NULL
                    ORDER BY a.id DESC
                    LIMIT :limit OFFSET :offset
                    """
                ),
                {"uid": user_id, "limit": limit, "offset": offset},
            ).mappings().all()
            return [dict(r) for r in rows]

    def get_article_by_id(self, article_id: int) -> dict | None:
        with get_db_connection() as conn:
            row = conn.execute(
                text(
                    """
                    SELECT
                      a.id, a.title, a.abstract, a.graphical_abstract, a.date, a.doi, a.llm_summary,
                      j.id AS journal_id, j.name AS journal_name, j.abbreviation
                    FROM articles a
                    JOIN journals j ON a.journal_id = j.id
                    WHERE a.id = :aid
                    """
                ),
                {"aid": article_id},
            ).mappings().first()
            return dict(row) if row else None

    def mark_as_read(self, user_id: int, article_ids: list[int]) -> bool:
        if not article_ids:
            return True

        ids = list(dict.fromkeys(int(x) for x in article_ids))  # 去重但保序
        with get_db_connection() as conn:
            count = conn.execute(
                text("SELECT COUNT(*) FROM articles WHERE id = ANY(:ids)"),
                {"ids": ids},
            ).scalar_one()

            if int(count) < len(ids):
                raise ValueError("One or more article IDs do not exist")

            conn.execute(
                text(
                    """
                    INSERT INTO user_article_reads (user_id, article_id)
                    SELECT :uid, x
                    FROM unnest(:ids::int[]) AS x
                    ON CONFLICT DO NOTHING
                    """
                ),
                {"uid": user_id, "ids": ids},
            )
            return True

    def add_favorite(self, user_id: int, article_id: int) -> bool:
        with get_db_connection() as conn:
            if not conn.execute(text("SELECT 1 FROM articles WHERE id = :aid"), {"aid": article_id}).first():
                raise ValueError("Article not found")

            inserted = conn.execute(
                text(
                    """
                    INSERT INTO user_article_favourites (user_id, article_id)
                    VALUES (:uid, :aid)
                    ON CONFLICT DO NOTHING
                    RETURNING id
                    """
                ),
                {"uid": user_id, "aid": article_id},
            ).scalar()

            return inserted is not None

    def del_favorite(self, user_id: int, article_id: int) -> bool:
        with get_db_connection() as conn:
            res = conn.execute(
                text(
                    """
                    DELETE FROM user_article_favourites
                    WHERE user_id = :uid AND article_id = :aid
                    """
                ),
                {"uid": user_id, "aid": article_id},
            )
            return (res.rowcount or 0) > 0

    def get_favorite_articles(self, user_id: int) -> list[int]:
        with get_db_connection() as conn:
            ids = conn.execute(
                text("SELECT article_id FROM user_article_favourites WHERE user_id = :uid"),
                {"uid": user_id},
            ).scalars().all()
            return [int(x) for x in ids]

    def get_read_articles(self, user_id: int) -> list[int]:
        with get_db_connection() as conn:
            ids = conn.execute(
                text("SELECT article_id FROM user_article_reads WHERE user_id = :uid"),
                {"uid": user_id},
            ).scalars().all()
            return [int(x) for x in ids]