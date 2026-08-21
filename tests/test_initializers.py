from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[1]
PROJECT_ARGS = [
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
]


def available_initializers() -> list[str]:
    available: list[str] = []
    if shutil.which("pwsh"):
        available.append("powershell")
    if shutil.which("bash"):
        available.append("bash")
    return available


@pytest.fixture(params=available_initializers())
def initializer(request: pytest.FixtureRequest) -> str:
    return str(request.param)


def copy_template(destination: Path) -> None:
    destination.mkdir()
    for source in ROOT.iterdir():
        if source.name == ".git":
            continue
        target = destination / source.name
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)


def run_initializer(
    initializer: str,
    checkout: Path,
    *,
    failure_at: str | None = None,
    keep_script: bool = True,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    if failure_at is not None:
        environment["TEMPLATE_INIT_FAIL_AT"] = failure_at
    else:
        environment.pop("TEMPLATE_INIT_FAIL_AT", None)

    if initializer == "powershell":
        command = [
            "pwsh",
            "-NoProfile",
            "-File",
            str(checkout / "scripts" / "init.ps1"),
            "-ProjectName",
            PROJECT_ARGS[0],
            "-Author",
            PROJECT_ARGS[2],
            "-AuthorEmail",
            PROJECT_ARGS[4],
            "-GitHubOwner",
            PROJECT_ARGS[6],
            "-Description",
            PROJECT_ARGS[8],
            "-Year",
            PROJECT_ARGS[10],
        ]
        if keep_script:
            command.append("-KeepScript")
    else:
        script_path = str(checkout / "scripts" / "init.sh")
        if os.name == "nt" and len(script_path) > 2 and script_path[1] == ":":
            script_path = (
                f"/mnt/{script_path[0].lower()}{script_path[2:].replace(os.sep, '/')}"
            )
        command = [
            "wsl.exe" if os.name == "nt" else "bash",
            *(
                ["env", f"TEMPLATE_INIT_FAIL_AT={failure_at}"]
                if os.name == "nt" and failure_at
                else []
            ),
            *(["bash"] if os.name == "nt" else []),
            script_path,
            "--project-name",
            *PROJECT_ARGS,
            "--keep-script",
        ]
        if not keep_script:
            command.pop()
    return subprocess.run(
        command,
        cwd=checkout,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )


def tree_snapshot(root: Path) -> dict[str, bytes | None]:
    snapshot: dict[str, bytes | None] = {}
    for path in sorted(root.rglob("*")):
        if ".git" in path.relative_to(root).parts:
            continue
        relative = path.relative_to(root).as_posix()
        snapshot[relative] = None if path.is_dir() else path.read_bytes()
    return snapshot


def test_successful_initializers_have_matching_output(
    initializer: str, tmp_path: Path
) -> None:
    first = tmp_path / "first"
    second = tmp_path / "second"
    copy_template(first)
    copy_template(second)

    first_result = run_initializer(initializer, first)
    second_result = run_initializer(
        "bash" if initializer == "powershell" else "powershell", second
    )

    assert first_result.returncode == 0, first_result.stderr
    assert second_result.returncode == 0, second_result.stderr
    assert tree_snapshot(first) == tree_snapshot(second)
    assert (first / "src" / "acme_widgets" / "__init__.py").exists()
    assert (first / ".claude" / "settings.json").exists()
    assert not (first / "TEMPLATE.md").exists()
    assert not (first / "docs").exists()


@pytest.mark.parametrize(
    "failure_at",
    [
        "content-write",
        "path-rename",
        "settings-activation",
        "template-removal",
        "apply-content-write",
        "apply-path-rename",
        "apply-settings-activation",
        "apply-template-removal",
    ],
)
def test_failure_injection_leaves_checkout_unchanged(
    initializer: str, failure_at: str, tmp_path: Path
) -> None:
    checkout = tmp_path / "checkout"
    copy_template(checkout)
    before = tree_snapshot(checkout)

    result = run_initializer(initializer, checkout, failure_at=failure_at)

    assert result.returncode != 0
    assert failure_at in result.stderr or failure_at in result.stdout
    assert tree_snapshot(checkout) == before
    assert not list(checkout.glob(".init-*"))


def test_preflight_conflict_leaves_checkout_unchanged(
    initializer: str, tmp_path: Path
) -> None:
    checkout = tmp_path / "checkout"
    copy_template(checkout)
    (checkout / "src" / "acme_widgets").mkdir()
    before = tree_snapshot(checkout)

    result = run_initializer(initializer, checkout)

    assert result.returncode != 0
    assert "conflict" in (result.stderr + result.stdout).lower()
    assert tree_snapshot(checkout) == before


def test_rerun_is_idempotent(initializer: str, tmp_path: Path) -> None:
    checkout = tmp_path / "checkout"
    copy_template(checkout)

    first = run_initializer(initializer, checkout)
    after_first = tree_snapshot(checkout)
    second = run_initializer(initializer, checkout)

    assert first.returncode == 0, first.stderr
    assert second.returncode == 0, second.stderr
    assert tree_snapshot(checkout) == after_first


def test_successful_run_removes_initializers_by_default(
    initializer: str, tmp_path: Path
) -> None:
    checkout = tmp_path / "checkout"
    copy_template(checkout)

    result = run_initializer(initializer, checkout, keep_script=False)

    assert result.returncode == 0, result.stderr
    assert not (checkout / "scripts" / "init.ps1").exists()
    assert not (checkout / "scripts" / "init.sh").exists()
