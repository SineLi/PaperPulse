"""Persist image retry attempts and cooldown."""

from alembic import op
import sqlalchemy as sa

revision = "f6a8c0d2e415"
down_revision = "e4b6f9a1c203"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("articles", sa.Column("ga_cache_attempts", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("articles", sa.Column("ga_cache_next_retry_at", sa.TIMESTAMP(timezone=True), nullable=True))
    op.create_index("ix_articles_image_retry", "articles", ["ga_cache_status", "ga_cache_next_retry_at", "id"])


def downgrade():
    op.drop_index("ix_articles_image_retry", table_name="articles")
    op.drop_column("articles", "ga_cache_next_retry_at")
    op.drop_column("articles", "ga_cache_attempts")
