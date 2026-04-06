import io
import base64
import logging
from pathlib import Path
from typing import TypedDict

import requests
from playwright.sync_api import sync_playwright
from PIL import Image, ImageOps, UnidentifiedImageError

logger = logging.getLogger(__name__)

_DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


class ImageCache(TypedDict):
    url: str
    path: str | None
    status: str
    error: str | None


class ImageService:
    _BUCKET_SIZE = 10000

    def __init__(
        self,
        media_root: str | Path | None = None,
        public_prefix: str = "/media/article-images",
        timeout: tuple[int, int] = (10, 30),
    ):
        base_dir = Path(__file__).resolve().parents[1]
        self._media_root = Path(media_root) if media_root else base_dir / "media"
        self._cache_dir = self._media_root / "article-images"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._public_prefix = public_prefix.rstrip("/")
        self._timeout = timeout
        self._session = requests.Session()
        self._session.headers.update(
            {
                "User-Agent": _DEFAULT_USER_AGENT,
                "Accept": "image/webp,image/*,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
            }
        )

    def cache_image(self, url: str, article_id: int) -> ImageCache:
        if not url:
            return ImageCache(url=url, path=None, status="invalid", error="empty_url")

        file_path = self.get_image_path(article_id, ensure_parent=True)
        relative_path = self._to_relative_path(file_path)

        if file_path.exists():
            return ImageCache(url=url, path=relative_path, status="exists", error=None)

        try:
            image_bytes = self._download_image(url)
            status = "cached"
        except requests.RequestException as exc:
            try: 
                image_bytes = self._download_image_with_playwright(url)
                status = "cached_with_playwright"
            except Exception as playwright_exc:
                error = self._build_download_failure_error(exc, playwright_exc)
                logger.warning("Failed to cache image from %s: %s", url, error)
                return ImageCache(url=url, path=None, status="failed", error=error)
        except Exception as exc:
            logger.warning("Failed to cache image from %s: %s", url, exc)
            return ImageCache(url=url, path=None, status="failed", error=str(exc))

        try:
            webp_bytes = self._convert_image(image_bytes)
            file_path.write_bytes(webp_bytes)
            return ImageCache(url=url, path=relative_path, status=status, error=None)
        except Exception as exc:
            logger.warning("Failed to process image from %s: %s", url, exc)
            return ImageCache(url=url, path=None, status="failed", error=str(exc))

    def build_public_url(self, article_id: int) -> str | None:
        if not self.has_cached_image(article_id):
            return None

        file_path = self.get_image_path(article_id)
        relative_path = self._to_relative_path(file_path)
        normalized = relative_path.replace("\\", "/").lstrip("/")
        return f"{self._public_prefix}/{normalized.removeprefix('article-images/')}"

    def _download_image_with_playwright(self, url: str) -> bytes:
        try:
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                try:
                    page = browser.new_page(
                        user_agent=_DEFAULT_USER_AGENT,
                        viewport={"width": 1920, "height": 1080},
                    )
                    response = page.goto(
                        url,
                        wait_until="networkidle",
                        timeout=self._timeout[1] * 1000,
                    )

                    body: bytes | None = None
                    if response is not None:
                        try:
                            body = response.body()
                        except Exception:
                            body = None
                        recovered_body = self._recover_invalid_navigation_image_body(page, url, response, body)
                        if recovered_body is not None:
                            body = recovered_body
                finally:
                    browser.close()

            if not body:
                raise ValueError("empty_image_response_playwright")
            if not self._is_supported_image_bytes(body):
                raise ValueError("invalid_image_data_playwright")

            return body
        except Exception as exc:
            raise ValueError(self._format_nested_error("playwright_fetch_failed", exc)) from exc

    def _download_image(self, url: str) -> bytes:
        headers = self._build_headers(url)
        response = self._session.get(
            url, headers=headers, timeout=self._timeout)
        response.raise_for_status()

        content_type = response.headers.get("Content-Type", "").lower()
        if content_type and not content_type.startswith("image/"):
            raise ValueError(f"unexpected_content_type:{content_type}")

        if not response.content:
            raise ValueError("empty_image_response")

        return response.content

    def _convert_image(self, image: bytes) -> bytes:
        try:
            with Image.open(io.BytesIO(image)) as img:
                normalized = ImageOps.exif_transpose(img)
                if normalized.mode not in ("RGB", "RGBA"):
                    normalized = normalized.convert("RGBA" if "A" in normalized.getbands() else "RGB")

                buffer = io.BytesIO()
                normalized.save(buffer, format="WEBP", quality=80, method=6)
                return buffer.getvalue()
        except UnidentifiedImageError as exc:
            raise ValueError("invalid_image_data") from exc

    def get_image(self, article_id: int) -> bytes | None:
        file_path = self._build_file_path(article_id)
        if not file_path.exists():
            return None
        return file_path.read_bytes()

    def get_image_path(self, article_id: int, ensure_parent: bool = False) -> Path:
        return self._build_file_path(article_id, ensure_parent=ensure_parent)

    def has_cached_image(self, article_id: int) -> bool:
        return self.get_image_path(article_id).exists()

    def _build_headers(self, url: str) -> dict[str, str]:
        host = requests.utils.urlparse(url)
        origin = f"{host.scheme}://{host.netloc}" if host.scheme and host.netloc else ""
        headers: dict[str, str] = {}
        if origin:
            headers["Referer"] = f"{origin}/"
        return headers

    def _recover_invalid_navigation_image_body(
        self,
        page,
        requested_url: str,
        response,
        body: bytes | None,
    ) -> bytes | None:
        content_type = response.headers.get("content-type", "").lower()
        if response.request.resource_type != "document":
            return None
        if not content_type.startswith("image/"):
            return None
        if body and self._is_supported_image_bytes(body):
            return None

        try:
            return self._load_image_body_via_cdp(page, requested_url)
        except Exception:
            return None

    def _load_image_body_via_cdp(self, page, requested_url: str) -> bytes:
        cdp = page.context.new_cdp_session(page)
        cdp.send("Page.enable")
        frame_tree = cdp.send("Page.getFrameTree")
        frame_id = frame_tree["frameTree"]["frame"]["id"]
        resource = cdp.send(
            "Network.loadNetworkResource",
            {
                "url": requested_url,
                "frameId": frame_id,
                "options": {"disableCache": False, "includeCredentials": True},
            },
        )

        if not resource["resource"].get("success"):
            raise ValueError("cdp_load_network_resource_failed")

        stream = resource["resource"].get("stream")
        if not stream:
            return b""

        chunks: list[bytes] = []
        while True:
            chunk = cdp.send("IO.read", {"handle": stream})
            data = chunk.get("data", "")
            if chunk.get("base64Encoded"):
                chunks.append(base64.b64decode(data))
            else:
                chunks.append(data.encode("utf-8", errors="replace"))
            if chunk.get("eof"):
                break

        cdp.send("IO.close", {"handle": stream})
        body = b"".join(chunks)
        if not self._is_supported_image_bytes(body):
            raise ValueError("cdp_invalid_image_data")
        return body

    def _is_supported_image_bytes(self, data: bytes) -> bool:
        if not data:
            return False
        try:
            with Image.open(io.BytesIO(data)) as img:
                img.verify()
            return True
        except (UnidentifiedImageError, OSError):
            return False

    def _build_download_failure_error(
        self,
        request_exc: Exception,
        playwright_exc: Exception,
    ) -> str:
        return (
            "download_failed:"
            f"requests={self._format_nested_error(type(request_exc).__name__, request_exc)};"
            f"playwright={self._format_nested_error(type(playwright_exc).__name__, playwright_exc)}"
        )

    def _format_nested_error(self, label: str, exc: Exception) -> str:
        messages = [label]
        current: BaseException | None = exc
        while current is not None:
            text = str(current).strip()
            if text and text not in messages:
                messages.append(text)
            current = current.__cause__
        return ":".join(messages)


    def _build_file_path(self, article_id: int, ensure_parent: bool = False) -> Path:
        if article_id <= 0:
            raise ValueError("invalid_article_id")
        bucket_dir = self._cache_dir / self._build_bucket_name(article_id)
        if ensure_parent:
            bucket_dir.mkdir(parents=True, exist_ok=True)
        return bucket_dir / f"{article_id}.webp"

    def _to_relative_path(self, file_path: Path) -> str:
        return file_path.relative_to(self._media_root).as_posix()

    def _build_bucket_name(self, article_id: int) -> str:
        bucket_start = ((article_id - 1) // self._BUCKET_SIZE) * self._BUCKET_SIZE + 1
        bucket_end = bucket_start + self._BUCKET_SIZE - 1
        return f"{bucket_start}-{bucket_end}"
