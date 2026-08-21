from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(
    not (REPO_ROOT / "TEMPLATE.md").is_file() or not (REPO_ROOT / "src/__PackageName__").is_dir(),
    reason="initializer tests require the uninitialized template",
)
_COPY_IGNORE = shutil.ignore_patterns(
    ".git",
    ".jj",
    ".venv",
    "dist",
    "build",
    "__pycache__",
)


def copy_template(tmp_path: Path) -> Path:
    checkout = tmp_path / "template"
    shutil.copytree(REPO_ROOT, checkout, ignore=_COPY_IGNORE)
    return checkout


def checkout_snapshot(checkout: Path) -> dict[str, str]:
    snapshot: dict[str, str] = {}
    for path in checkout.rglob("*"):
        if path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            snapshot[path.relative_to(checkout).as_posix()] = digest
    return snapshot


def subprocess_environment(checkout: Path) -> dict[str, str]:
    environment = os.environ.copy()
    # Keep defaults deterministic and independent of the developer's global Git config.
    environment.update(
        {
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": str(checkout / "missing-global-config"),
            "GIT_CONFIG_SYSTEM": str(checkout / "missing-system-config"),
        }
    )
    return environment


def run_posix(checkout: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "scripts/init.sh", *arguments],
        cwd=checkout,
        env=subprocess_environment(checkout),
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize(
    "option",
    [
        "--project-name",
        "--author",
        "--author-email",
        "--github-owner",
        "--description",
        "--year",
    ],
)
def test_posix_rejects_terminal_missing_values_before_mutation(tmp_path: Path, option: str) -> None:
    checkout = copy_template(tmp_path)
    before = checkout_snapshot(checkout)

    result = run_posix(checkout, option)

    assert result.returncode != 0
    assert option in result.stderr
    assert "requires a value" in result.stderr
    assert checkout_snapshot(checkout) == before


def test_posix_accepts_all_values_and_keeps_scripts(tmp_path: Path) -> None:
    checkout = copy_template(tmp_path)

    result = run_posix(
        checkout,
        "--project-name",
        "acme-widgets",
        "--author",
        "Jane Doe",
        "--author-email",
        "jane@example.com",
        "--github-owner",
        "acme",
        "--description",
        "Widget toolkit",
        "--year",
        "2026",
        "--keep-script",
    )

    assert result.returncode == 0, result.stderr
    assert (checkout / "src/acme_widgets/__init__.py").is_file()
    assert 'name = "acme-widgets"' in (checkout / "pyproject.toml").read_text()
    assert 'description = "Widget toolkit"' in (checkout / "pyproject.toml").read_text()
    assert 'name = "Jane Doe"' in (checkout / "pyproject.toml").read_text()
    assert 'email = "jane@example.com"' in (checkout / "pyproject.toml").read_text()
    assert "Widget toolkit" in (checkout / "README.md").read_text()
    assert "github.com/acme/acme-widgets" in (checkout / "CHANGELOG.md").read_text()
    release_workflow = (checkout / ".github/workflows/release.yml").read_text()
    assert 'git config user.name "Jane Doe"' in release_workflow
    assert 'git config user.email "jane@example.com"' in release_workflow
    assert "Copyright (c) 2026 Jane Doe" in (checkout / "LICENSE").read_text()
    assert (checkout / "scripts/init.sh").is_file()
    assert (checkout / "scripts/init.ps1").is_file()


def test_posix_preserves_explicit_empty_values_as_current_defaults(tmp_path: Path) -> None:
    checkout = copy_template(tmp_path)

    result = run_posix(
        checkout,
        "--project-name",
        "acme-widgets",
        "--author",
        "",
        "--description",
        "",
        "--keep-script",
    )

    assert result.returncode == 0, result.stderr
    pyproject = (checkout / "pyproject.toml").read_text()
    assert 'description = "TODO: project description"' in pyproject
    assert 'name = "Your Name"' in pyproject


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
@pytest.mark.parametrize(
    ("parameter", "argument"),
    [
        ("-Author", "Author"),
        ("-AuthorEmail", "AuthorEmail"),
        ("-GitHubOwner", "GitHubOwner"),
        ("-Description", "Description"),
        ("-Year", "Year"),
    ],
)
def test_powershell_rejects_terminal_missing_values_before_mutation(
    tmp_path: Path, parameter: str, argument: str
) -> None:
    checkout = copy_template(tmp_path)
    before = checkout_snapshot(checkout)

    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(checkout / "scripts/init.ps1"),
            "-ProjectName",
            "acme-widgets",
            parameter,
        ],
        cwd=checkout,
        env=subprocess_environment(checkout),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert argument in result.stderr
    assert checkout_snapshot(checkout) == before


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
def test_powershell_preserves_explicit_empty_values_as_current_defaults(tmp_path: Path) -> None:
    checkout = copy_template(tmp_path)

    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(checkout / "scripts/init.ps1"),
            "-ProjectName",
            "acme-widgets",
            "-Author",
            "",
            "-Description",
            "",
            "-KeepScript",
        ],
        cwd=checkout,
        env=subprocess_environment(checkout),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    pyproject = (checkout / "pyproject.toml").read_text()
    assert 'description = "TODO: project description"' in pyproject
    assert 'name = "Your Name"' in pyproject


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
def test_powershell_rejects_missing_project_name_before_mutation(tmp_path: Path) -> None:
    checkout = copy_template(tmp_path)
    before = checkout_snapshot(checkout)

    result = subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(checkout / "scripts/init.ps1")],
        cwd=checkout,
        env=subprocess_environment(checkout),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "ProjectName" in result.stderr
    assert checkout_snapshot(checkout) == before
