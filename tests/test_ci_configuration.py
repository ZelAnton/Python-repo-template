from __future__ import annotations

import tomllib
from pathlib import Path

ROOT = Path(__file__).parents[1]


def test_ci_tests_template_and_generated_copy_separately() -> None:
    workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text()

    assert workflow.count("name: Prepare generated repository") == 6
    assert workflow.count("git archive --format=tar HEAD") == 6
    assert workflow.count('generated_dir="$(mktemp -d)"') == 6
    assert "bash ./scripts/init.sh --project-name template-self-test" not in workflow
    assert "uv run --no-project --with pytest pytest" in workflow
    assert (
        "tests/test_initializers.py tests/test_init_cli.py tests/test_init_scripts.py" in workflow
    )
    assert "tests/test_ci_configuration.py" in workflow
    assert 'uv --directory "$GENERATED_REPOSITORY" run --locked pytest' in workflow


def test_yaml_lint_job_uses_the_locked_uv_environment() -> None:
    workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text()

    assert "astral-sh/setup-uv@" in workflow
    assert "run --locked yamllint ." in workflow
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
