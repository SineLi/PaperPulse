import asyncio
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch

from app.version import APP_VERSION


sync_api = types.ModuleType("patchright.sync_api")
sync_api.sync_playwright = object()
sys.modules.setdefault("patchright.sync_api", sync_api)

from services.image_service import ImageService


class FakeSession:
    def __init__(self):
        self.headers = {}


class ImageServiceTests(unittest.IsolatedAsyncioTestCase):
    def test_non_image_http_response_falls_back_to_patchright(self):
        with tempfile.TemporaryDirectory() as media_root:
            service = ImageService(media_root=media_root)
            with (
                patch.object(
                    service,
                    "_download_image",
                    side_effect=ValueError("unexpected_content_type:text/html"),
                ),
                patch.object(
                    service,
                    "_download_image_with_playwright",
                    return_value=b"browser-image",
                ) as browser_download,
                patch.object(service, "_convert_image", return_value=b"webp"),
            ):
                result = service.cache_image("https://example.com/image", 1)

        self.assertEqual(result["status"], "cached_with_playwright")
        self.assertIsNone(result["error"])
        browser_download.assert_called_once_with("https://example.com/image")

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
        self.assertEqual(first.headers["User-Agent"], f"PaperPulse/{APP_VERSION}")
        self.assertEqual(first.headers["User-Agent"], second.headers["User-Agent"])


if __name__ == "__main__":
    unittest.main()
