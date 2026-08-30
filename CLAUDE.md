# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests (warnings are promoted to errors).
uv run pytest

# Lint and format check.
uv run ruff check .
uv run ruff format --check .

# Type-check (strict).
uv run mypy

# Build the wheel + sdist.
uv build
```

`uv run` provisions the pinned Python (`.python-version`), creates the
virtualenv, and syncs dependencies automatically — there is no separate install
step.

## Architecture

> **Fill this in for `__ProjectName__`.** Describe the public surface, the main
> modules, and any non-obvious design decisions so an agent can navigate the code
> without re-deriving the structure each time.

The source lives in `src/__PackageName__/` (the importable package) and tests in
`tests/`. Keep the public API surface small and intentional, re-export it from
`src/__PackageName__/__init__.py`, keep implementation details internal, and
prefer simple, direct code over new abstractions.

## Conventions

See [AGENTS.md](AGENTS.md) for the authoritative conventions: dependencies,
formatting, type-checking, error-handling style, changelog rules, and the release
process. The most load-bearing rules:

- Lint (`ruff`), strict typing (`mypy`), and warning-free tests are gates; keep
  the public API minimal and intentional.
- Every user-visible change ships its `CHANGELOG.md` entry under `## [Unreleased]`
  in the same change set (auto-fill from git log is a fallback, not the default).
- The release workflow's publish step is the single irreversible pivot — see
  AGENTS.md → "Release".

## Agent instruction files (in repos created from this template)

This applies to a repo **created from a template**, not the template itself (here
they stay tracked and pushed). Downstream, keep `CLAUDE.md`, `AGENTS.md`, and
`.claude/` **git-ignored and untracked** so they stay on disk for tooling but never
reach the remote — a by-hand step before the first push (the init script does not do
it). Recipe: the "Agent instruction files are local-only in generated repos" section
of [AGENTS.md](AGENTS.md), or `docs/AGENT-INIT-GUIDE.md` while it exists.

## Version control workflow

The repo uses Git directly. Do not initialize or colocate another version-control
system in the working tree. Use a feature branch per pull request (never advance
`main` locally), and sync only on the user's explicit `pull`/`push` trigger. Full
workflow in [AGENTS.md](AGENTS.md) → "Version control".
