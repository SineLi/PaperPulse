import os
import unittest
from unittest.mock import patch

from db import database


class DatabaseConfigTests(unittest.TestCase):
    def tearDown(self):
        database._ENGINE = None

    def test_engine_applies_database_timeouts(self):
        engine = object()
        environment = {
            "DATABASE_URL": "postgresql+psycopg://user:password@db:5432/paperpulse",
            "DB_CONNECT_TIMEOUT_SECS": "7",
            "DB_POOL_TIMEOUT_SECS": "8",
            "DB_STATEMENT_TIMEOUT_MS": "9000",
            "DB_LOCK_TIMEOUT_MS": "4000",
        }

        with (
            patch.dict(os.environ, environment, clear=True),
            patch.object(database, "create_engine", return_value=engine) as create_engine,
        ):
            result = database.get_engine()

        self.assertIs(result, engine)
        create_engine.assert_called_once_with(
            environment["DATABASE_URL"],
            pool_pre_ping=True,
            pool_timeout=8,
            connect_args={
                "connect_timeout": 7,
                "options": "-c statement_timeout=9000 -c lock_timeout=4000",
            },
            future=True,
        )

    def test_rejects_non_positive_timeout(self):
        with patch.dict(
            os.environ,
            {
                "DATABASE_URL": "postgresql+psycopg://user:password@db:5432/paperpulse",
                "DB_STATEMENT_TIMEOUT_MS": "0",
            },
            clear=True,
        ):
            with self.assertRaisesRegex(
                RuntimeError,
                "DB_STATEMENT_TIMEOUT_MS must be a positive integer",
            ):
                database.get_engine()


if __name__ == "__main__":
    unittest.main()
