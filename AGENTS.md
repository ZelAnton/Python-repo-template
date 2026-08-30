# AGENTS.md

## Project

- This repository contains `__ProjectName__`, a Python project.
- The public API lives in `src/__PackageName__/` (the importable package), re-exported from `src/__PackageName__/__init__.py`.
- Tests live in `tests/` (`test_*.py`, discovered by pytest).
- Keep the repository focused; do not introduce CLI, UI, hosting, logging, or dependency injection infrastructure unless explicitly requested.

## Agent instruction files are local-only in generated repos

> **Scope:** this section is for a repository **created from a template**, not the
> template itself. In the template, `CLAUDE.md`, `AGENTS.md`, and `.claude/` stay
> **tracked and pushed** — that is how the guidance ships. If you are reading this
> in the template repo, leave them tracked and do nothing.

In a generated repo, `CLAUDE.md`, `AGENTS.md`, and `.claude/` are local guidance for whoever (human or agent) works in the clone — not project source. Keep them **git-ignored and untracked** so they stay on disk for tooling but never reach the remote; each developer keeps their own. This is a **by-hand step — the init script does not do it** — done **before the first push**:

```bash
# Append last so `.claude/` overrides the earlier `!.claude/...` ship lines.
printf '\n/CLAUDE.md\n/AGENTS.md\n.claude/\n' >> .gitignore
git rm -r --cached CLAUDE.md AGENTS.md .claude
git add .gitignore && git commit -m "Keep agent instructions local"   # commit the ignore rule *and* the removals together
```

`git rm --cached` keeps the files on disk; an ignore rule alone won't untrack already-committed files. `init` deletes `TEMPLATE.md` and `docs/AGENT-INIT-GUIDE.md`, so this section is the surviving copy of the recipe downstream — consult that guide while it exists for precedence details and the caveat that a repo created via GitHub's *Use this template* already carries these files in its initial commit's history (untracking drops them from the tip only).

## Runtime

- Use Python (3.12 or later). The floor is declared once, in `pyproject.toml` (`requires-python`) and `.python-version`; do not change it unless explicitly asked.
- Use [uv](https://docs.astral.sh/uv/) for everything: it provisions the interpreter, manages the virtualenv, installs dependencies, runs the tooling, and builds. Do not hand-manage a venv or call `pip` directly.

## Dependencies

- Do not introduce new dependencies without explicit approval.
- Add runtime dependencies with `uv add <pkg>` (they land in `pyproject.toml` `[project.dependencies]`); add dev tools with `uv add --dev <pkg>` (the `dev` dependency group). Never hand-edit version pins ad hoc.
- **Commit `uv.lock`.** It is the resolved, reproducible dependency set — tracked, not ignored. Run `uv lock` after changing dependencies and commit the result.
- The supply-chain audit tool is `pip-audit` (a CI job scans the resolved tree against the PyPI Advisory Database). Treat a new advisory like a build failure.

## Architecture

- Keep all functionality available as reusable library APIs.
- Keep implementation details (helpers, platform-specific code, internal types) internal to the library.
- Do not expose implementation types publicly unless explicitly requested.
- Prefer simple, direct code over new abstractions.
- Minimize public API surface area; public API changes must be intentional and documented.
- Do not add dependency injection unless there is a concrete need.

## Build, references, and repository structure

- Source lives under `src/__PackageName__/` (a [src layout](https://packaging.python.org/en/latest/discussions/src-layout-vs-flat-layout/) — the package is import-tested as installed, not from the working dir), tests under `tests/`, helper scripts under `scripts/`.
- `pyproject.toml` is the single project manifest: build backend (hatchling), metadata, dependencies, and tool config (ruff, mypy, pytest) all live there.
- Re-export the public surface from `src/__PackageName__/__init__.py`; reach into submodules for internals only.

## Build And Test

- Use `uv run pytest` to run tests. Tests run with warnings promoted to errors (`filterwarnings = ["error"]`).
- Use `uv run mypy` (strict) as the type gate and `uv run ruff check .` as the lint gate — both are CI-enforced and play the role "warnings are errors" does in a compiled language.
- A successful test run must execute the discovered tests, not only collect them.

## Formatting

- `.editorconfig` is the source of truth for indentation and line endings of non-Python files; `ruff format` owns `.py` formatting.
- The formatter is `uv run ruff format .`; CI runs `ruff format --check .` and the lint set must be clean.
- Preserve LF line endings, except Windows batch files (`.cmd`/`.bat`) which require CRLF.

## Python Style

- Target the pinned Python version's idioms; `ruff`'s `UP` (pyupgrade) rules modernize syntax automatically.
- **Type everything.** Public functions, parameters, and returns carry annotations; `mypy --strict` is enforced (no untyped defs, no implicit `Any`). Use `from __future__ import annotations` only where it helps.
- Prefer standard-library and built-in solutions over new dependencies. Minimize public API surface.
- Follow PEP 8 / PEP 257 (ruff enforces the relevant subset). Use `snake_case` for functions/variables, `PascalCase` for classes.

### Exception / error handling style

- Prefer multi-line, explicit handlers over collapsed one-liners. Catch the narrowest exception type that applies, not bare `except:` / `except Exception`.
- An empty/ignored `except` branch must carry a comment explaining **what** is being swallowed and **why** ignoring is correct here. A bare `pass` alone is not enough.

  ```python
  try:
      config = load_config(path)
  except FileNotFoundError:
      # No config on disk is expected on first run; fall back to defaults.
      config = default_config()
  ```

## Documentation

- All documentation and code comments must be written in English.
- Functional changes must include corresponding README updates when behavior, requirements, usage, or public API changes.
- Do not leave changed behavior undocumented.

## Changelog

- `CHANGELOG.md` is the single source of truth for release notes.
- The release workflow reads `## [Unreleased]` automatically to populate the GitHub Release body.
- **Every user-visible change must be accompanied by a `CHANGELOG.md` update in the same change set.** Non-negotiable for new/modified public API, behavioural changes, bug fixes, deprecations, removals. Pure internal refactors are the only exemption.
- Add a manual bullet under `## [Unreleased]` in the appropriate subsection (`### Added` / `### Changed` / `### Fixed` / `### Removed` / `### Deprecated`). Write it for a consumer, not the implementer. Replace the placeholder `-`.
- Do not modify versioned sections (`## [1.0.0]`, etc.) — those are managed by the release workflow.

### Auto-fill fallback

- If `## [Unreleased]` has no real bullets at release time, the workflow auto-generates entries from commits since the previous tag using `git-cliff` (config: `cliff.toml`). Manual entries always win.
- The first word of the commit subject decides the bucket (case-insensitive): `Add`/`Feat` → Added; `Fix`/`Bug` → Fixed; `Remove`/`Delete`/`Drop` → Removed; `Refactor`/`Update`/`Change`/`Rename`/`Perf`/`CI`/`Cleanup` → Changed; `Doc`/`Chore`/`Test`/`Style` and `Release v...`/merges → skipped; anything else → Changed (fallback).

## Release

- The release workflow (`.github/workflows/release.yml`) publishes to PyPI and attaches the built wheel + sdist plus a `SHA256SUMS` manifest to the GitHub Release.
- Publishing requires the `PYPI_API_TOKEN` repository secret (or switch to PyPI Trusted Publishing / OIDC — see the publish step's comment).
- The version is single-source in `pyproject.toml` (`[project] version`). The workflow computes the next version from the latest `v*` tag (or seeds the first release from the manifest), writes it back into `pyproject.toml` **before** building so the wheel carries it, then commits and tags.
- **Step ordering invariant:** the PyPI publish is the only irreversible step, so it is the pivot. A secret preflight runs first; build/test/package and a *local* (unpushed) commit+tag run before the pivot; the publish runs next; the atomic commit+tag push to `main` and the idempotent GitHub Release run after. A failure before or at the publish leaves no remote/registry trace — re-run freely. **Once the tag is pushed to `main`, do not re-run the whole workflow** — finish the GitHub Release manually using the command the failing step prints. When editing `release.yml`, never move the publish after the tag push, and keep the post-pivot steps idempotent.

## Security Scanning

- **CodeQL** (`.github/workflows/codeql.yml`) runs GitHub's static analysis on `main` pushes/PRs and weekly. Python is CodeQL-supported (`build-mode: none`, since Python is interpreted).
- **pip-audit** (a CI job) scans the resolved dependency tree against the PyPI Advisory Database and fails on a known vulnerability.
- **Dependabot** keeps Actions and Python packages current.

## Comments

- Minimize comments. Write them only to explain why something exists, an architectural decision, or non-obvious platform/runtime behavior.
- Do not write comments describing what the code already says.

## Version control (Git)

This repository uses Git directly. Do not initialize or colocate another version-control system in the working tree.

### Starting work

- Before editing, run `git status --short --branch` and inspect the current branch and any existing changes.
- Keep refinements and follow-ups for the same task on the current feature branch.
- Do not mix unrelated work into the same branch or commit. If the working tree is clean, create a short kebab-case feature branch from `origin/main`. If unrelated work arrives while changes are still in progress, ask before stashing, switching branches, or creating another worktree.
- Preserve user-authored changes and do not amend or rewrite their commits without explicit agreement.

### Pushing to remote

The user signals "synchronise with remote" with a short trigger word (typically `pull` or `push`). On that signal, run the full sync:
1. `git fetch origin` — pull down remote movement before doing anything else.
2. Rebase the feature branch onto `origin/main` when the remote branch has advanced: `git rebase origin/main`.
3. Push the feature branch, never local `main`: use `git push --set-upstream origin HEAD` on the first push and `git push` afterwards.
4. Open or update a pull request into `main` (`gh pr create --base main --head <topic> --fill`). `main` advances only when the pull request merges; afterwards, fetch, update local `main` with a fast-forward-only pull, and delete the merged feature branch.

Never push without an explicit signal from the user. **Direct-push fallback:** where `main` is unprotected, `git push origin HEAD:main` remains available; once pull requests are required this is rejected for everyone except the release workflow's GitHub App, which sits in the ruleset's bypass list (`RELEASE_APP_ID` + `RELEASE_APP_PRIVATE_KEY`; see `release-token-bypass.md`).

### Undoing work

- **`git restore <path>`** discards selected unstaged changes; use `git restore --staged <path>` to unstage without deleting work.
- **`git revert <commit>`** reverses a published commit without rewriting shared history.
- **`git reflog`** locates earlier branch and `HEAD` positions when recovery is needed.
- Do not use `git reset --hard`, force-push, or rewrite published history without explicit approval.

Never hide a deliberate undo. Tell the user exactly which files or commits were reverted.

### Branches & safety

- Work is published through a **feature branch per pull request** (short kebab-case topic name), merged into `main` via pull request.
- Do not revert or amend changes the user authored without explicit agreement.
- Do not rewrite unrelated files when making a focused change.

## Command Conventions

- Commands and APIs should be idempotent where possible.
- Output should remain concise and script-friendly.
- Breaking changes must be explicit.
