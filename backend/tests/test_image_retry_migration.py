import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text


class ImageRetryMigrationTests(unittest.TestCase):
    def test_upgrade_preserves_rows_and_downgrade_removes_retry_fields(self):
        path = Path(__file__).resolve().parents[1] / "db/alembic/versions/f6a8c0d2e415_add_image_retry_backoff.py"
        spec = importlib.util.spec_from_file_location("image_retry_migration", path)
        migration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(migration)
        engine = create_engine("sqlite://")
        self.addCleanup(engine.dispose)
        with engine.begin() as conn:
            conn.execute(text("CREATE TABLE articles (id INTEGER PRIMARY KEY, ga_cache_status TEXT)"))
            conn.execute(text("INSERT INTO articles VALUES (1, 'failed')"))
            operations = Operations(MigrationContext.configure(conn))
            with patch.object(migration, "op", operations):
                migration.upgrade()
                row = conn.execute(text("SELECT * FROM articles")).mappings().one()
                self.assertEqual(row["ga_cache_status"], "failed")
                self.assertEqual(row["ga_cache_attempts"], 0)
                self.assertIsNone(row["ga_cache_next_retry_at"])
                self.assertIn("ix_articles_image_retry", [index["name"] for index in inspect(conn).get_indexes("articles")])
                migration.downgrade()
                columns = [column["name"] for column in inspect(conn).get_columns("articles")]
                self.assertEqual(columns, ["id", "ga_cache_status"])
                self.assertEqual(conn.execute(text("SELECT COUNT(*) FROM articles")).scalar_one(), 1)
