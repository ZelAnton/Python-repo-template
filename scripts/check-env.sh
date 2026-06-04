#!/usr/bin/env bash
#
# Checks this machine can build and test the generated Python project before you
# run scripts/init.sh (POSIX counterpart of check-env.ps1 — use whichever matches
# your shell; both do the same thing).
#
# Verifies the uv toolchain is on PATH. uv drives everything (it provisions the
# Python interpreter pinned by .python-version, creates the virtualenv, installs
# dependencies, runs lint/type/test, and builds), so it is the only hard
# requirement. Exits 0 when ready; if uv is missing it prints per-OS install
# commands and exits 1 — install it, then re-run.
#
# Usage: bash ./scripts/check-env.sh

set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,15p' "$0"; exit 0 ;; esac

problems=()
echo "==> Checking environment for Python development"

# Required: uv (build/test/lint/format driver). It bootstraps the pinned Python
# itself, so no separate `python` is needed on PATH.
if command -v uv >/dev/null 2>&1; then
  echo "    $(uv --version)"
else
  problems+=("the uv toolchain ('uv' is not on PATH)")
fi

# Soft: git drives init's author/email defaults and the VCS workflow, but is not
# required to build.
command -v git >/dev/null 2>&1 || \
  echo "    note: git is not on PATH — init falls back to placeholder author/email."

if [ ${#problems[@]} -eq 0 ]; then
  echo
  echo "Environment ready. Next: bash ./scripts/init.sh --project-name ..."
  echo "(uv installs the pinned Python from .python-version on the first 'uv run'.)"
  exit 0
fi

echo
echo "Environment NOT ready. Missing:"
for p in "${problems[@]}"; do echo "  - $p"; done
echo
echo "Install uv, then re-run this check:"
echo "  Windows : winget install --id=astral-sh.uv -e   (or: irm https://astral.sh/uv/install.ps1 | iex)"
echo "  macOS   : brew install uv                        (or: curl -LsSf https://astral.sh/uv/install.sh | sh)"
echo "  Linux   : curl -LsSf https://astral.sh/uv/install.sh | sh"
echo "  (any OS) : see https://docs.astral.sh/uv/getting-started/installation/"
exit 1
