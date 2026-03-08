"""create initial postgres schema

Revision ID: 9a7cc9f15801
Revises: 
Create Date: 2026-03-02 19:38:02.324582

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "9a7cc9f15801"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # users
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("username", sa.Text(), nullable=False, unique=True),
        sa.Column("email", sa.Text(), nullable=False, unique=True),
        # 0: banned 1: normal 2: vip 3: admin
        sa.Column("role", sa.Integer(), nullable=False,
                  server_default=sa.text("1")),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
    )
    op.create_check_constraint("ck_users_role", "users", "role in (0,1,2,3)")

    # journals
    op.create_table(
        "journals",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.Text(), nullable=False, unique=True),
        sa.Column("abbreviation", sa.Text(), nullable=True),
        sa.Column("if", sa.Float(), nullable=True),
        sa.Column("if5", sa.Float(), nullable=True),
        sa.Column("sci", sa.Integer(), nullable=False,
                  server_default=sa.text("0")),
        sa.Column("casup", sa.Text(), nullable=True),
        sa.Column("casbase", sa.Text(), nullable=True),
        sa.Column("publisher", sa.Text(), nullable=True),
        sa.Column("issn", sa.Text(), nullable=True),
        sa.Column("eissn", sa.Text(), nullable=True),
        sa.Column("official_url", sa.Text(), nullable=True),
        sa.Column("rss_url", sa.Text(), nullable=True),
        sa.Column("crawler_enabled", sa.Boolean(), nullable=False,
                  server_default=sa.text("false")),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
    )

    # articles
    op.create_table(
        "articles",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("link", sa.Text(), nullable=False, unique=True),
        sa.Column("doi", sa.Text(), nullable=True, unique=True),
        sa.Column("date", sa.Date(), nullable=True),
        sa.Column("journal_id", sa.Integer(), sa.ForeignKey(
            "journals.id"), nullable=True),
        sa.Column("authors", sa.Text(), nullable=True),
        sa.Column("editor_summary", sa.Text(), nullable=True),
        sa.Column("structured_abstract", sa.Text(), nullable=True),
        sa.Column("abstract", sa.Text(), nullable=True),
        sa.Column("graphical_abstract", sa.Text(), nullable=True),
        sa.Column("llm_summary", sa.Text(), nullable=True),
        sa.Column("llm_status", sa.Text(), nullable=True),
        sa.Column("status", sa.Text(), nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.Column("processed_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )

    # user_journal_subscriptions
    op.create_table(
        "user_journal_subscriptions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey(
            "users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("journal_id", sa.Integer(), sa.ForeignKey(
            "journals.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("user_id", "journal_id", name="uq_user_journal"),
    )

    # user_article_favourites
    op.create_table(
        "user_article_favourites",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey(
            "users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("article_id", sa.Integer(), sa.ForeignKey(
            "articles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("user_id", "article_id",
                            name="uq_user_article_fav"),
    )

    # user_article_reads
    op.create_table(
        "user_article_reads",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey(
            "users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("article_id", sa.Integer(), sa.ForeignKey(
            "articles.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("user_id", "article_id",
                            name="uq_user_article_read"),
    )

    # non_article_entries
    op.create_table(
        "non_article_entries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("link", sa.Text(), nullable=False, unique=True),
        sa.Column("date", sa.Text(), nullable=True),  # 第一版先不升级，避免导入失败
        sa.Column("journal_id", sa.Integer(), sa.ForeignKey(
            "journals.id"), nullable=False),
        sa.Column("doi", sa.Text(), nullable=True, unique=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
    )

    op.create_index("idx_articles_doi", "articles", ["doi"])
    op.create_index("idx_articles_link", "articles", ["link"])
    op.create_index("idx_articles_date", "articles", ["date"])
    op.create_index("idx_journals_name", "journals", ["name"])
    op.create_index("idx_ujs_journal",
                    "user_journal_subscriptions", ["journal_id"])
    op.create_index("idx_uaf_article",
                    "user_article_favourites", ["article_id"])
    op.create_index("idx_uar_article", "user_article_reads", ["article_id"])

    # 自动更新journals表的updated_at字段
    op.execute("""
        CREATE OR REPLACE FUNCTION set_updated_at()
        RETURNS trigger AS $$
        BEGIN
        NEW.updated_at = now();
        RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    """)

    op.execute("""
        DROP TRIGGER IF EXISTS trg_journals_set_updated_at ON journals;
        CREATE TRIGGER trg_journals_set_updated_at
        BEFORE UPDATE ON journals
        FOR EACH ROW
        EXECUTE FUNCTION set_updated_at();
    """)


def downgrade():
    op.drop_index("idx_uar_article", table_name="user_article_reads")
    op.drop_index("idx_uaf_article", table_name="user_article_favourites")
    op.drop_index("idx_ujs_journal", table_name="user_journal_subscriptions")
    op.drop_index("idx_journals_name", table_name="journals")
    op.drop_index("idx_articles_date", table_name="articles")
    op.drop_index("idx_articles_link", table_name="articles")
    op.drop_index("idx_articles_doi", table_name="articles")

    op.drop_table("non_article_entries")
    op.drop_table("user_article_reads")
    op.drop_table("user_article_favourites")
    op.drop_table("user_journal_subscriptions")
    op.drop_table("articles")
    op.drop_table("journals")
    op.drop_table("users")
