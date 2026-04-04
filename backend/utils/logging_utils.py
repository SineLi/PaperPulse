import logging
import sys
from typing import Any

LOG_FORMAT = "%(asctime)s | %(levelname)-7s | %(name)s | %(message)s"
LOG_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


class RealTimeFileHandler(logging.FileHandler):
    def emit(self, record):
        super().emit(record)
        self.flush()


def configure_logging(*, level: int = logging.INFO, logfile: str | None = None, force: bool = False):
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    if logfile:
        handlers.append(RealTimeFileHandler(logfile, encoding="utf-8"))

    logging.basicConfig(
        level=level,
        format=LOG_FORMAT,
        datefmt=LOG_DATE_FORMAT,
        handlers=handlers,
        force=force,
    )


def _format_value(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:.3f}"

    text = str(value).replace("\r", "\\r").replace("\n", "\\n").replace("|", "/")
    if not text:
        return '""'
    if any(ch.isspace() for ch in text) or "=" in text:
        escaped = text.replace('"', '\\"')
        return f'"{escaped}"'
    return text


def format_event(event: str, **fields: Any) -> str:
    parts = [f"event={event}"]
    for key, value in fields.items():
        if value is None:
            continue
        parts.append(f"{key}={_format_value(value)}")
    return " ".join(parts)


def log_event(logger: logging.Logger, level: int, event: str, **fields: Any):
    logger.log(level, format_event(event, **fields))
