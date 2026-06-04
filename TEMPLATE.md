# Python repository template

A starting point for Python repositories: a pinned interpreter (via uv), strict
linting and typing (ruff + mypy --strict), warning-free pytest, cross-platform
CI, CodeQL + pip-audit scanning, an optional PyPI release pipeline, and
conventions for agents in [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md).

> **AI agents:** before initializing a repo from this template, read
> [docs/AGENT-INIT-GUIDE.md](docs/AGENT-INIT-GUIDE.md). It captures mistakes past
> initialization sessions made and is a living document you are expected to extend.

## Using this template

1. Create a new repository from this one (GitHub: **Use this template**), or copy
   the files into a fresh repo.
2. **Check your environment is ready.** Before initializing, confirm this machine
   has the toolchain to build and test a Python project. Use whichever matches
   your shell — both do the same thing:

   ```pwsh
   pwsh ./scripts/check-env.ps1
   ```

   ```bash
   bash ./scripts/check-env.sh
   ```

   It checks that [uv](https://docs.astral.sh/uv/) is on PATH (uv provisions the
   pinned Python itself). If anything required is missing it lists the install
   commands for your OS and exits non-zero — install what it names, then re-run
   it. **Don't run init until it reports the environment is ready.**
3. Run the init script once to stamp your project name in. Use whichever matches
   your shell — both do the same thing:

   ```pwsh
   pwsh ./scripts/init.ps1 -ProjectName acme-widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
   ```

   ```bash
   bash ./scripts/init.sh --project-name acme-widgets --author "Jane Doe" --github-owner acme --description "Widget toolkit"
   ```

   `-ProjectName` / `--project-name` is required; the rest fall back to sensible
   defaults. The script replaces the placeholder tokens in file contents, derives
   the importable package name and renames `src/__PackageName__` to it, renames
   any other token-named files/folders, activates `.claude/settings.json` from its
   `.template` form, deletes this `TEMPLATE.md` and `docs/AGENT-INIT-GUIDE.md`, and
   (unless `-KeepScript` / `--keep-script`) removes **both** initializers
   (`check-env.{ps1,sh}` stay — they double as a contributor onboarding check).
4. Verify:

   ```sh
   uv run pytest
   ```

5. Replace the placeholder `greet` function in `src/<package>/` with your real API
   and delete the sample test.
6. **Keep the agent-instruction files local.** This template tracks and ships
   `CLAUDE.md`, `AGENTS.md`, and `.claude/` on purpose — but a repo *created from*
   it should keep them out of its remote. The init script does **not** do this — it
   is a by-hand step. Before your first push, git-ignore and untrack them:

   ```bash
   printf '\n/CLAUDE.md\n/AGENTS.md\n.claude/\n' >> .gitignore
   git rm -r --cached CLAUDE.md AGENTS.md .claude
   git add .gitignore && git commit -m "Keep agent instructions local"
   # jj-colocated: jj file untrack CLAUDE.md AGENTS.md .claude
   ```

   Appending `.claude/` last makes it win over the earlier `!.claude/...` ship
   lines. The surviving copy of this recipe downstream is the "Agent instruction
   files are local-only in generated repos" section of [AGENTS.md](AGENTS.md).

## Placeholder tokens

| Token | Meaning |
|---|---|
| `__ProjectName__` | PyPI distribution / repo name, used verbatim (URLs, `pyproject` `name`, LICENSE) |
| `__PackageName__` | **derived** importable package (snake_case from `__ProjectName__`); names `src/<package>/` and the imports |
| `__Author__` | author (LICENSE, package metadata) |
| `__AuthorEmail__` | author email (package metadata + release-commit identity in `release.yml`) |
| `__GitHubOwner__` | GitHub owner/org in repository URLs |
| `__Description__` | package description |
| `__Year__` | copyright year |

## Optional pieces — remove what you don't need

- **PyPI publishing** — if this is an app or internal library, delete
  `.github/workflows/release.yml`, the `[project.urls]` block, and trim packaging
  metadata in `pyproject.toml`.
- **Community-health files** — `SECURITY.md`, `CONTRIBUTING.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`, `.github/CODEOWNERS`. Edit to taste; delete
  any you don't want. `CODEOWNERS` ships with its rule commented out.
- **YAML linting** — `.yamllint.yml` + the CI `yaml-lint` job. Run locally with
  `uvx yamllint .`. Delete both if unwanted.
- **CodeQL** — `.github/workflows/codeql.yml`. Delete it if you don't want GitHub's
  static analysis.

## Security hardening (on by default)

- **Pinned actions** — every GitHub Action is pinned to a full commit SHA (with a
  `# vN` comment). Dependabot bumps the SHA and rewrites the comment.
- **Dependency auditing** — `pip-audit` runs in CI and fails on a PyPI advisory in
  the resolved tree; CodeQL adds static analysis.
- **Release ordering** — the workflow publishes to PyPI as the single irreversible
  pivot, then pushes the tag, so a blocked push can't orphan a release.

## Post-setup checklist

- [ ] Agent-instruction files (`CLAUDE.md`, `AGENTS.md`, `.claude/`) git-ignored and
      untracked (by hand, before the first push — step 6 above).
- [ ] `PYPI_API_TOKEN` repository secret added (only if publishing).
- [ ] LICENSE author/year reviewed; package metadata in `pyproject.toml` filled in.
- [ ] `uv.lock` generated (`uv lock`) and committed.
- [ ] `SECURITY.md` reporting contact reviewed; `.github/CODEOWNERS` enabled if wanted.
- [ ] GitHub **Settings → Security → Private vulnerability reporting** enabled.
- [ ] `CLAUDE.md` "Architecture" section written for your project.
- [ ] Branch protection for `main` configured; if PRs are required, set up the
      release App token (`RELEASE_APP_ID` + `RELEASE_APP_PRIVATE_KEY`; recipe:
      `release-token-bypass.md`).
