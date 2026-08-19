import asyncio
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch


sync_api = types.ModuleType("playwright.sync_api")
sync_api.sync_playwright = object()
sys.modules.setdefault("playwright.sync_api", sync_api)

from services.image_service import ImageService


class FakeSession:
    def __init__(self):
        self.headers = {}


class ImageServiceTests(unittest.IsolatedAsyncioTestCase):
    async def test_concurrent_workers_use_distinct_sessions(self):
        barrier = threading.Barrier(2)
        sessions: list[FakeSession] = []

        def create_session():
            session = FakeSession()
            sessions.append(session)
            return session

        with tempfile.TemporaryDirectory() as media_root:
            with patch("services.image_service.requests.Session", side_effect=create_session):
                service = ImageService(media_root=media_root)

                def get_session_in_worker():
                    barrier.wait()
                    return service._get_session()

                first, second = await asyncio.gather(
                    asyncio.to_thread(get_session_in_worker),
                    asyncio.to_thread(get_session_in_worker),
                )

        self.assertIsNot(first, second)
        self.assertEqual(len(sessions), 2)
        self.assertEqual(first.headers["User-Agent"], second.headers["User-Agent"])


if __name__ == "__main__":
    unittest.main()
