import hashlib
import io
import logging
from pathlib import Path
from typing import TypedDict

import requests
from PIL import Image, ImageOps, UnidentifiedImageError

logger = logging.getLogger(__name__)

_DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")


class ImageCache(TypedDict):
    url: str
    path: str | None
    status: str
    error: str | None


class ImageService:
    def __init__(
        self,
        media_root: str | Path | None = None,
        public_prefix: str = "/media/article-images",
        timeout: tuple[int, int] = (10, 30),
    ):
        base_dir = Path(__file__).resolve().parents[1]
        self._media_root = Path(
            media_root) if media_root else base_dir / "media"
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

    def cache_image(self, url: str, hash: str | None = None) -> ImageCache:
        if not url:
            return ImageCache(url=url, path=None, status="invalid", error="empty_url")

        cache_key = self._normalize_cache_key(hash, url)
        file_path = self._cache_dir / f"{cache_key}.webp"
        relative_path = file_path.relative_to(self._media_root).as_posix()

        if file_path.exists():
            return ImageCache(url=url, path=relative_path, status="exists", error=None)

        try:
            image_bytes = self._download_image(url)
            webp_bytes = self._convert_image(image_bytes)
            file_path.write_bytes(webp_bytes)
            return ImageCache(url=url, path=relative_path, status="cached", error=None)
        except Exception as exc:
            logger.warning("Failed to cache image from %s: %s", url, exc)
            return ImageCache(url=url, path=None, status="failed", error=str(exc))

    def build_public_url(self, path: str | None) -> str | None:
        if not path:
            return None
        normalized = path.replace("\\", "/").lstrip("/")
        return f"{self._public_prefix}/{normalized.removeprefix('article-images/')}"

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
                    normalized = normalized.convert(
                        "RGBA" if "A" in normalized.getbands() else "RGB")

                buffer = io.BytesIO()
                normalized.save(buffer, format="WEBP", quality=80, method=6)
                return buffer.getvalue()
        except UnidentifiedImageError as exc:
            raise ValueError("invalid_image_data") from exc

    def get_image(self, hash: str) -> bytes | None:
        file_path = self._cache_dir / f"{self._normalize_cache_key(hash)}.webp"
        if not file_path.exists():
            return None
        return file_path.read_bytes()

    def get_image_path(self, hash: str) -> Path:
        return self._cache_dir / f"{self._normalize_cache_key(hash)}.webp"

    def _build_headers(self, url: str) -> dict[str, str]:
        host = requests.utils.urlparse(url)
        origin = f"{host.scheme}://{host.netloc}" if host.scheme and host.netloc else ""
        headers: dict[str, str] = {}
        if origin:
            headers["Referer"] = f"{origin}/"
        return headers

    def _normalize_cache_key(self, hash_value: str | None = None, url: str | None = None) -> str:
        if hash_value:
            return "".join(ch for ch in hash_value.lower() if ch.isalnum() or ch in ("-", "_"))
        if url:
            return hashlib.sha256(url.encode("utf-8")).hexdigest()
        raise ValueError("missing_cache_key")


if __name__ == "__main__":
    service = ImageService()
    result = service.cache_image("https://pubs.acs.org/cms/10.1021/acs.analchem.5c07921/asset/images/medium/ac5c07921_0006.gif")
    print(result)