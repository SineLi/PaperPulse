import logging
from typing import Any

import requests
from curl_cffi import requests as curl_requests

logger = logging.getLogger(__name__)

CURL_IMPERSONATE = "chrome"


def impersonated_get(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    fallback_headers: dict[str, str] | None = None,
    timeout: float | int,
) -> Any:
    """GET with a browser TLS/HTTP fingerprint, falling back on transport errors."""

    try:
        return curl_requests.get(
            url,
            headers=headers,
            impersonate=CURL_IMPERSONATE,
            timeout=timeout,
        )
    except curl_requests.RequestsError as exc:
        logger.warning("event=curl_cffi_get_failed url=%s detail=%s", url, exc)
        return requests.get(
            url,
            headers=fallback_headers if fallback_headers is not None else headers,
            timeout=timeout,
        )


def impersonated_head(url: str, *, timeout: float | int) -> Any:
    """HEAD with a browser TLS/HTTP fingerprint, falling back on transport errors."""

    try:
        return curl_requests.head(
            url,
            impersonate=CURL_IMPERSONATE,
            timeout=timeout,
        )
    except curl_requests.RequestsError as exc:
        logger.warning("event=curl_cffi_head_failed url=%s detail=%s", url, exc)
        return requests.head(url, timeout=timeout)
