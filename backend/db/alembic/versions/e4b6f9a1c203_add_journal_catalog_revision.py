"""add journal catalog revision

Revision ID: e4b6f9a1c203
Revises: c7d8e9f0a112
Create Date: 2026-08-31 00:00:00.000000

"""

from alembic import op
import sqlalchemy as sa


revision = "e4b6f9a1c203"
down_revision = "c7d8e9f0a112"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "journal_catalog_state",
        sa.Column("id", sa.Boolean(), primary_key=True),
        sa.Column(
            "revision", sa.BigInteger(), nullable=False, server_default=sa.text("1")
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("id", name="ck_journal_catalog_state_singleton"),
    )
    op.execute(
        "INSERT INTO journal_catalog_state (id, revision) VALUES (TRUE, 1)"
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION bump_journal_catalog_revision()
        RETURNS trigger AS $$
        BEGIN
            UPDATE journal_catalog_state
            SET revision = revision + 1, updated_at = now()
            WHERE id = TRUE;
            RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    catalog_columns = (
        "name, abbreviation, \"if\", if5, sci, casup, casbase, publisher, "
        "official_url, rss_url"
    )
    op.execute(
        f"""
        CREATE TRIGGER trg_journal_catalog_insert
        AFTER INSERT ON journals
        FOR EACH STATEMENT EXECUTE FUNCTION bump_journal_catalog_revision();

        CREATE TRIGGER trg_journal_catalog_update
        AFTER UPDATE OF {catalog_columns} ON journals
        FOR EACH STATEMENT EXECUTE FUNCTION bump_journal_catalog_revision();

        CREATE TRIGGER trg_journal_catalog_delete
        AFTER DELETE ON journals
        FOR EACH STATEMENT EXECUTE FUNCTION bump_journal_catalog_revision();
        """
    )


def downgrade():
    op.execute("DROP TRIGGER IF EXISTS trg_journal_catalog_delete ON journals")
    op.execute("DROP TRIGGER IF EXISTS trg_journal_catalog_update ON journals")
    op.execute("DROP TRIGGER IF EXISTS trg_journal_catalog_insert ON journals")
    op.execute("DROP FUNCTION IF EXISTS bump_journal_catalog_revision()")
    op.drop_table("journal_catalog_state")
