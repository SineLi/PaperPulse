"""add ga cache status

Revision ID: c7d8e9f0a112
Revises: 9a7cc9f15801
Create Date: 2026-03-17 10:15:00.000000

"""

from alembic import op
import sqlalchemy as sa


revision = "c7d8e9f0a112"
down_revision = "9a7cc9f15801"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("articles", sa.Column("ga_cache_status", sa.Text(), nullable=True))
    op.execute(
        """
        UPDATE articles
        SET ga_cache_status = 'pending'
        WHERE graphical_abstract IS NOT NULL
          AND graphical_abstract != ''
        """
    )


def downgrade():
    op.drop_column("articles", "ga_cache_status")
