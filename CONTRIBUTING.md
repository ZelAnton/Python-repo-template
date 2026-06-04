# Contributing to __ProjectName__

Thanks for your interest in improving **__ProjectName__**.

## Prerequisites

- Python 3.12 (uv provisions the exact interpreter pinned in `.python-version`).
- [uv](https://docs.astral.sh/uv/) on your PATH — run `scripts/check-env.sh`
  (or `scripts/check-env.ps1`) to confirm.

## Build and test

```sh
uv run pytest                       # run the tests
uv run ruff format --check .        # formatting must be clean
uv run ruff check .                 # lint
uv run mypy                         # type-check (strict)
uv build                            # build the wheel + sdist
```

`ruff check`, `mypy --strict`, and `pytest` (with warnings promoted to errors)
are the gates CI enforces, so run them locally before opening a pull request.

## Conventions

- **Formatting and linting** are governed by [`ruff`](https://docs.astral.sh/ruff/)
  (config in [`pyproject.toml`](pyproject.toml)). Run `uv run ruff format .` to
  apply formatting; don't reformat code you are not changing.
- **Dependencies** are declared in `pyproject.toml` and pinned in `uv.lock`
  (commit the lockfile). Add them with `uv add`, not by hand.
- See [`AGENTS.md`](AGENTS.md) for the full, authoritative set of conventions.

## Changelog

Every user-visible change ships its [`CHANGELOG.md`](CHANGELOG.md) entry in the
same change set, under `## [Unreleased]`. Write the bullet for a consumer of the
library, not the implementer. Pure internal refactors are exempt.

## Pull requests

- Keep changes focused; unrelated cleanups belong in their own PR.
- Ensure CI (lint, type-check, and tests on Linux, Windows, macOS) passes.
- Fill in the pull-request checklist.
