import os
import unittest
from unittest.mock import patch

from utils import redis_client


class RedisClientInitTests(unittest.TestCase):
    def tearDown(self):
        redis_client._client = None

    def test_rejects_missing_redis_url(self):
        redis_client._client = None
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "REDIS_URL is not configured"):
                redis_client.init_client()

    def test_preserves_initialization_exception_as_cause(self):
        redis_client._client = None
        with (
            patch.dict(os.environ, {"REDIS_URL": "redis://example"}),
            patch.object(redis_client, "RedisClient", side_effect=ValueError("invalid URL")),
        ):
            with self.assertRaisesRegex(RuntimeError, "Failed to initialize Redis client") as raised:
                redis_client.init_client()

        self.assertIsInstance(raised.exception.__cause__, ValueError)


if __name__ == "__main__":
    unittest.main()
