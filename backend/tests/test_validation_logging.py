import json
import unittest
from unittest.mock import patch

from fastapi.exceptions import RequestValidationError
from starlette.requests import Request

from app.main import validation_exception_handler


class ValidationLoggingTests(unittest.IsolatedAsyncioTestCase):
    async def test_validation_log_excludes_rejected_input(self):
        secret = "short-password"
        error = {
            "type": "string_too_short",
            "loc": ("body", "password"),
            "msg": "String should have at least 16 characters",
            "input": secret,
            "ctx": {"min_length": 16},
        }
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "path": "/register",
                "headers": [],
                "query_string": b"",
                "server": ("testserver", 80),
                "client": ("testclient", 123),
                "scheme": "http",
            }
        )

        with patch("app.main.logger.warning") as warning:
            response = await validation_exception_handler(
                request,
                RequestValidationError([error]),
            )

        logged_errors = warning.call_args.args[-1]
        self.assertEqual(
            logged_errors,
            [{"type": "string_too_short", "loc": ("body", "password")}],
        )
        self.assertNotIn(secret, repr(logged_errors))
        self.assertEqual(json.loads(response.body)["detail"][0]["input"], secret)


if __name__ == "__main__":
    unittest.main()
