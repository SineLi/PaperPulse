import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
PUBSPEC_FILE = ROOT / "frontend_app" / "pubspec.yaml"
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
PUBSPEC_PATTERN = re.compile(r"^version:\s*([^\s]+)", flags=re.MULTILINE)


def validate(version: str) -> str:
    version = version.strip()
    if not VERSION_PATTERN.fullmatch(version):
        raise SystemExit(f"Unsupported semantic version: {version!r}")
    return version


def read_versions() -> tuple[str, str]:
    project_version = validate(VERSION_FILE.read_text(encoding="utf-8"))
    pubspec = PUBSPEC_FILE.read_text(encoding="utf-8")
    match = PUBSPEC_PATTERN.search(pubspec)
    if match is None:
        raise SystemExit("frontend_app/pubspec.yaml does not declare a version")
    return project_version, match.group(1).split("+")[0]


def check() -> None:
    project_version, frontend_version = read_versions()
    if frontend_version != project_version.split("+")[0]:
        raise SystemExit(
            "Version mismatch: "
            f"VERSION={project_version}, frontend={frontend_version}"
        )
    print(f"PaperPulse version {project_version} is consistent")


def set_version(version: str) -> None:
    version = validate(version)
    pubspec = PUBSPEC_FILE.read_text(encoding="utf-8")
    updated_pubspec, replacements = PUBSPEC_PATTERN.subn(
        f"version: {version}", pubspec, count=1
    )
    if replacements != 1:
        raise SystemExit("frontend_app/pubspec.yaml does not declare a version")

    VERSION_FILE.write_text(f"{version}\n", encoding="utf-8")
    PUBSPEC_FILE.write_text(updated_pubspec, encoding="utf-8")
    print(f"Updated PaperPulse to {version}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage the PaperPulse version")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check", help="verify all version declarations")
    set_parser = subparsers.add_parser("set", help="update all version declarations")
    set_parser.add_argument("version", help="new semantic version")
    args = parser.parse_args()

    if args.command == "check":
        check()
    else:
        set_version(args.version)


if __name__ == "__main__":
    main()
