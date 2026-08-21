from __future__ import annotations

import os
import shutil
import subprocess
import tomllib
from collections.abc import Iterator
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parents[1]
SAFE_VALUES = {
    "project_name": "acme-widgets",
    "author": "Jane Doe",
    "author_email": "jane@example.com",
    "github_owner": "acme",
    "description": "Widget toolkit: fast, safe!",
    "year": "2026",
}


def _bash_executable() -> str:
    if os.name == "nt":
        candidates = [
            r"C:\Program Files\Git\bin\bash.exe",
            r"C:\Program Files\Git\usr\bin\bash.exe",
            shutil.which("bash"),
        ]
    else:
        candidates = [shutil.which("bash")]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    pytest.skip("bash is required to test init.sh")


def _pwsh_executable() -> str:
    executable = shutil.which("pwsh")
    if executable:
        return executable
    pytest.skip("pwsh is required to test init.ps1")


@pytest.fixture(params=("sh", "ps1"))
def initializer(request: pytest.FixtureRequest) -> Iterator[tuple[str, str]]:
    if request.param == "sh":
        yield request.param, _bash_executable()
    else:
        yield request.param, _pwsh_executable()


def _copy_template(tmp_path: Path) -> Path:
    tmp_path.mkdir(parents=True, exist_ok=True)
    target = tmp_path / "template"
    shutil.copytree(
        REPO_ROOT,
        target,
        ignore=shutil.ignore_patterns(".git", ".jj", ".venv", "build", "dist", "__pycache__"),
    )
    return target


def _run_initializer(
    root: Path,
    kind: str,
    executable: str,
    values: dict[str, str],
) -> subprocess.CompletedProcess[str]:
    if kind == "sh":
        command = [
            executable,
            "-c",
            'exec scripts/init.sh --project-name "$T001_PROJECT_NAME" '
            '--author "$T001_AUTHOR" --author-email "$T001_AUTHOR_EMAIL" '
            '--github-owner "$T001_GITHUB_OWNER" --description "$T001_DESCRIPTION" '
            '--year "$T001_YEAR" --keep-script',
            "init.sh",
        ]
        environment = os.environ.copy()
        environment.update(
            {
                "T001_PROJECT_NAME": values["project_name"],
                "T001_AUTHOR": values["author"],
                "T001_AUTHOR_EMAIL": values["author_email"],
                "T001_GITHUB_OWNER": values["github_owner"],
                "T001_DESCRIPTION": values["description"],
                "T001_YEAR": values["year"],
            }
        )
    else:
        command = [
            executable,
            "-NoProfile",
            "-File",
            "scripts/init.ps1",
            "-ProjectName",
            values["project_name"],
            "-Author",
            values["author"],
            "-AuthorEmail",
            values["author_email"],
            "-GitHubOwner",
            values["github_owner"],
            "-Description",
            values["description"],
            "-Year",
            values["year"],
            "-KeepScript",
        ]
        environment = None
    return subprocess.run(
        command, cwd=root, capture_output=True, text=True, check=False, env=environment
    )


def _snapshot(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob("*")
        if path.is_file()
    }


def test_safe_metadata_is_written_and_release_shell_stays_literal(
    tmp_path: Path, initializer: tuple[str, str]
) -> None:
    kind, executable = initializer
    root = _copy_template(tmp_path)

    result = _run_initializer(root, kind, executable, SAFE_VALUES)

    assert result.returncode == 0, result.stdout + result.stderr
    assert (root / "src" / "acme_widgets" / "__init__.py").is_file()
    assert not (root / "src" / "__PackageName__").exists()
    assert not (root / "TEMPLATE.md").exists()
    assert not (root / "docs" / "AGENT-INIT-GUIDE.md").exists()
    pyproject = (root / "pyproject.toml").read_text()
    metadata = tomllib.loads(pyproject)["project"]
    assert metadata["name"] == "acme-widgets"
    assert metadata["description"] == "Widget toolkit: fast, safe!"
    assert metadata["authors"] == [{"name": "Jane Doe", "email": "jane@example.com"}]
    assert 'name = "acme-widgets"' in pyproject
    assert 'description = "Widget toolkit: fast, safe!"' in pyproject
    assert 'name = "Jane Doe", email = "jane@example.com"' in pyproject
    release = (root / ".github" / "workflows" / "release.yml").read_text()
    assert 'git config user.name "Jane Doe"' in release
    assert 'git config user.email "jane@example.com"' in release
    assert "__Author__" not in release
    assert "__AuthorEmail__" not in release


@pytest.mark.parametrize(
    ("field", "dangerous"),
    (
        ("author", 'Bad"Name'),
        ("author_email", r"bad\mail@example.com"),
        ("github_owner", "bad\nowner"),
        ("description", "$(touch pwned); echo hacked"),
    ),
)
def test_unsafe_metadata_is_rejected_without_partial_mutation(
    tmp_path: Path,
    initializer: tuple[str, str],
    field: str,
    dangerous: str,
) -> None:
    kind, executable = initializer
    root = _copy_template(tmp_path)
    before = _snapshot(root)
    values = SAFE_VALUES.copy()
    values[field] = dangerous

    result = _run_initializer(root, kind, executable, values)

    assert result.returncode != 0
    assert "unsafe" in (result.stdout + result.stderr).lower()
    assert _snapshot(root) == before
    assert not (root / "pwned").exists()


@pytest.mark.parametrize("separator", ("\u0085", "\u2028", "\u2029"))
@pytest.mark.parametrize("field", ("author", "author_email", "github_owner", "description"))
def test_unicode_control_and_line_separators_are_rejected_without_mutation(
    tmp_path: Path,
    initializer: tuple[str, str],
    field: str,
    separator: str,
) -> None:
    kind, executable = initializer
    root = _copy_template(tmp_path)
    before = _snapshot(root)
    values = SAFE_VALUES.copy()
    values[field] = f"safe{separator}value"

    result = _run_initializer(root, kind, executable, values)

    assert result.returncode != 0
    assert "unsafe" in (result.stdout + result.stderr).lower()
    assert _snapshot(root) == before


@pytest.mark.parametrize(
    "description",
    (
        "[click](https://example.invalid)",
        "# heading",
        "*emphasis*",
        "- [ ] task",
        "- list item",
        "+ list item",
        "1. ordered item",
        "1) ordered item",
        "---",
        "- - -",
        "    indented code",
        "\tindented code",
    ),
)
def test_markdown_description_syntax_is_rejected_without_mutation(
    tmp_path: Path,
    initializer: tuple[str, str],
    description: str,
) -> None:
    kind, executable = initializer
    root = _copy_template(tmp_path)
    before = _snapshot(root)
    values = SAFE_VALUES | {"description": description}

    result = _run_initializer(root, kind, executable, values)

    assert result.returncode != 0
    assert "markdown" in (result.stdout + result.stderr).lower()
    assert _snapshot(root) == before


@pytest.mark.parametrize(
    "description",
    (
        "- list item",
        "+ list item",
        "1. ordered item",
        "---",
        "- - -",
        "    indented code",
        "\tindented code",
    ),
)
def test_markdown_block_rejection_has_power_shell_and_posix_parity(
    tmp_path: Path, description: str
) -> None:
    bash = _bash_executable()
    pwsh = _pwsh_executable()
    posix_root = _copy_template(tmp_path / "posix")
    powershell_root = _copy_template(tmp_path / "powershell")
    values = SAFE_VALUES | {"description": description}
    posix_before = _snapshot(posix_root)
    powershell_before = _snapshot(powershell_root)

    posix_result = _run_initializer(posix_root, "sh", bash, values)
    powershell_result = _run_initializer(powershell_root, "ps1", pwsh, values)

    assert posix_result.returncode != 0
    assert powershell_result.returncode != 0
    assert "markdown" in (posix_result.stdout + posix_result.stderr).lower()
    assert "markdown" in (powershell_result.stdout + powershell_result.stderr).lower()
    assert _snapshot(posix_root) == posix_before
    assert _snapshot(powershell_root) == powershell_before


@pytest.mark.parametrize("kind", ("sh", "ps1"))
def test_invalid_github_owner_is_rejected_without_partial_mutation(
    tmp_path: Path, kind: str
) -> None:
    executable = _bash_executable() if kind == "sh" else _pwsh_executable()
    root = _copy_template(tmp_path)
    before = _snapshot(root)
    values = SAFE_VALUES | {"github_owner": "owner/name"}

    result = _run_initializer(root, kind, executable, values)

    assert result.returncode != 0
    assert "github owner" in (result.stdout + result.stderr).lower()
    assert _snapshot(root) == before


def test_power_shell_and_posix_outputs_have_parity(tmp_path: Path) -> None:
    bash = _bash_executable()
    pwsh = _pwsh_executable()
    posix_root = _copy_template(tmp_path / "posix")
    powershell_root = _copy_template(tmp_path / "powershell")

    posix_result = _run_initializer(posix_root, "sh", bash, SAFE_VALUES)
    powershell_result = _run_initializer(powershell_root, "ps1", pwsh, SAFE_VALUES)

    assert posix_result.returncode == 0, posix_result.stdout + posix_result.stderr
    assert powershell_result.returncode == 0, powershell_result.stdout + powershell_result.stderr
    assert _snapshot(posix_root) == _snapshot(powershell_root)
