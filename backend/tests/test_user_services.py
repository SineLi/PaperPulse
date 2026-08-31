import unittest
from unittest.mock import MagicMock, patch

from services.user_services import UserService


class UserServiceJournalTests(unittest.TestCase):
    def test_available_journals_exposes_cas_fields_with_api_contract_names(self):
        connection = MagicMock()
        connection.execute.return_value.mappings.return_value.all.return_value = [
            {
                "id": 7,
                "name": "Example Journal",
                "sci": 1,
                "if": 9.5,
                "if5": 8.4,
                "CASUp": "一区",
                "CASBase": "二区",
                "publisher": "Example Publisher",
                "abbreviation": "Ex. J.",
            }
        ]
        connection_context = MagicMock()
        connection_context.__enter__.return_value = connection

        with patch(
            "services.user_services.get_db_connection",
            return_value=connection_context,
        ):
            journals = UserService.__new__(UserService).get_available_journals(
                limit=10,
                offset=20,
            )

        statement = str(connection.execute.call_args.args[0])
        self.assertIn('casup AS "CASUp"', statement)
        self.assertIn('casbase AS "CASBase"', statement)
        self.assertEqual(journals[0]["CASUp"], "一区")
        self.assertEqual(journals[0]["CASBase"], "二区")
        self.assertEqual(
            connection.execute.call_args.args[1],
            {"limit": 10, "offset": 20},
        )

    def test_catalog_status_returns_revision_and_available_count(self):
        connection = MagicMock()
        connection.execute.return_value.mappings.return_value.one.return_value = {
            "revision": 42,
            "count": 120,
        }
        connection_context = MagicMock()
        connection_context.__enter__.return_value = connection

        with patch(
            "services.user_services.get_db_connection",
            return_value=connection_context,
        ):
            status = UserService.__new__(UserService).get_journal_catalog_status()

        statement = str(connection.execute.call_args.args[0])
        self.assertIn("journal_catalog_state", statement)
        self.assertIn("official_url IS NOT NULL OR j.rss_url IS NOT NULL", statement)
        self.assertEqual(status, {"revision": "42", "count": 120})


if __name__ == "__main__":
    unittest.main()
