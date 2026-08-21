from __future__ import annotations

import tomllib
from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_yaml_lint_job_uses_the_locked_uv_environment() -> None:
    workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text()

    assert "astral-sh/setup-uv@" in workflow
    assert "uv run --locked yamllint ." in workflow
    assert "pip install yamllint" not in workflow
    assert (ROOT / ".yamllint.yml").is_file()


def test_yamllint_is_exactly_pinned_in_manifest_and_lock() -> None:
    manifest = tomllib.loads((ROOT / "pyproject.toml").read_text())
    dev_dependencies = manifest["dependency-groups"]["dev"]

    assert "yamllint==1.37.1" in dev_dependencies

    lock = (ROOT / "uv.lock").read_text()
    assert 'name = "yamllint"' in lock
    assert 'version = "1.37.1"' in lock
    assert 'name = "pathspec"' in lock
    assert 'name = "pyyaml"' in lock
