import unittest
from unittest.mock import Mock, patch

from curl_cffi import requests as curl_requests

from utils.http_client import impersonated_get, impersonated_head


class HttpClientTests(unittest.TestCase):
    def test_get_uses_chrome_impersonation(self):
        response = Mock()
        with patch("utils.http_client.curl_requests.get", return_value=response) as get:
            result = impersonated_get(
                "https://example.com/feed",
                headers={"Accept": "application/xml"},
                timeout=20,
            )

        self.assertIs(result, response)
        get.assert_called_once_with(
            "https://example.com/feed",
            headers={"Accept": "application/xml"},
            impersonate="chrome",
            timeout=20,
        )

    def test_get_falls_back_to_requests_on_curl_transport_error(self):
        response = Mock()
        with (
            patch(
                "utils.http_client.curl_requests.get",
                side_effect=curl_requests.RequestsError("transport failed"),
            ),
            patch("utils.http_client.requests.get", return_value=response) as get,
        ):
            result = impersonated_get(
                "https://example.com/feed",
                headers={"Accept": "application/xml"},
                fallback_headers={"User-Agent": "PaperPulse/Test"},
                timeout=20,
            )

        self.assertIs(result, response)
        get.assert_called_once_with(
            "https://example.com/feed",
            headers={"User-Agent": "PaperPulse/Test"},
            timeout=20,
        )

    def test_head_uses_chrome_impersonation(self):
        response = Mock()
        with patch("utils.http_client.curl_requests.head", return_value=response) as head:
            result = impersonated_head("https://example.com/image", timeout=5)

        self.assertIs(result, response)
        head.assert_called_once_with(
            "https://example.com/image",
            impersonate="chrome",
            timeout=5,
        )


if __name__ == "__main__":
    unittest.main()
