import os
from pathlib import Path


def _load_version() -> str:
    injected_version = os.getenv("PAPERPULSE_VERSION", "").strip()
    if injected_version:
        return injected_version

    version_file = Path(__file__).resolve().parents[2] / "VERSION"
    if version_file.is_file():
        version = version_file.read_text(encoding="utf-8").strip()
        if version:
            return version

    raise RuntimeError(
        "PaperPulse version is unavailable; set PAPERPULSE_VERSION or provide VERSION"
    )


APP_VERSION = _load_version()
