import html
import re

_TITLE_PATTERN = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
_META_REFRESH_PATTERN = re.compile(
    r"<meta[^>]+http-equiv\s*=\s*['\"]?refresh['\"]?[^>]*>",
    re.IGNORECASE,
)
_SHORT_CHALLENGE_MAX_CHARS = 12_000


def detect_block_reason(
    content: str,
    current_url: str = "",
    title: str = "",
) -> str | None:
    """Recognize challenge pages without matching incidental anti-bot scripts."""

    text = content or ""
    lower_text = text.lower()
    normalized_title = (title or _extract_title(text)).lower()

    title_hints = (
        "just a moment",
        "attention required",
        "verify you are human",
        "access denied",
        "are you a robot",
    )
    for hint in title_hints:
        if hint in normalized_title:
            return f"title:{hint}"

    structural_hints = (
        "challenge-platform",
        "cf-chl",
        "cf-please-wait",
        "cdn-cgi/challenge",
        "turnstile-widget",
    )
    for hint in structural_hints:
        if hint in lower_text:
            return f"content:{hint}"

    lower_url = (current_url or "").lower()
    url_hints = ("cdn-cgi", "__cf_chl", "bm-verify", "captcha")
    for hint in url_hints:
        if hint in lower_url:
            return f"url:{hint}"

    stripped = lower_text.strip()
    if len(stripped) <= _SHORT_CHALLENGE_MAX_CHARS:
        if "bm-verify" in stripped:
            return "content:bm-verify"
        if _META_REFRESH_PATTERN.search(stripped) and any(
            marker in stripped
            for marker in ("verify", "challenge", "captcha", "akamai", "_abck")
        ):
            return "content:verification-meta-refresh"

    return None


def _extract_title(content: str) -> str:
    match = _TITLE_PATTERN.search(content)
    if match is None:
        return ""
    return html.unescape(re.sub(r"\s+", " ", match.group(1))).strip()
