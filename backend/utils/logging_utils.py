import logging
import sys
from typing import Any

LOG_FORMAT = "[%(levelname)s] [%(asctime)s] [%(name)s] %(message)s"
LOG_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


class RealTimeFileHandler(logging.FileHandler):
    def emit(self, record):
        super().emit(record)
        self.flush()


def _build_formatter() -> logging.Formatter:
    return logging.Formatter(fmt=LOG_FORMAT, datefmt=LOG_DATE_FORMAT)


def configure_logging(*, level: int = logging.INFO, logfile: str | None = None, force: bool = False):
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    if logfile:
        handlers.append(RealTimeFileHandler(logfile, encoding="utf-8"))

    formatter = _build_formatter()
    for handler in handlers:
        handler.setFormatter(formatter)

    logging.basicConfig(
        level=level,
        handlers=handlers,
        force=force,
    )


def build_uvicorn_log_config(level: int = logging.INFO) -> dict[str, Any]:
    level_name = logging.getLevelName(level)
    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {
                "format": LOG_FORMAT,
                "datefmt": LOG_DATE_FORMAT,
            },
            "access": {
                "format": LOG_FORMAT,
                "datefmt": LOG_DATE_FORMAT,
            },
        },
        "handlers": {
            "default": {
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stdout",
                "formatter": "default",
            },
            "access": {
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stdout",
                "formatter": "access",
            },
        },
        "loggers": {
            "uvicorn": {
                "handlers": ["default"],
                "level": level_name,
                "propagate": False,
            },
            "uvicorn.error": {
                "handlers": ["default"],
                "level": level_name,
                "propagate": False,
            },
            "uvicorn.access": {
                "handlers": ["access"],
                "level": level_name,
                "propagate": False,
            },
        },
    }


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
