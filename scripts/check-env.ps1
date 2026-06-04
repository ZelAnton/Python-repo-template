#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Checks this machine can build and test the generated Python project before
    you run scripts/init.ps1.

.DESCRIPTION
    POSIX counterpart: scripts/check-env.sh — use whichever matches your shell.

    Verifies the uv toolchain is on PATH. uv drives everything (it provisions the
    Python interpreter pinned by .python-version, creates the virtualenv, installs
    dependencies, runs lint/type/test, and builds), so it is the only hard
    requirement. Prints "Environment ready" and exits 0 on success; if uv is
    missing it prints per-OS install commands and exits 1 — install it, then
    re-run:

        pwsh ./scripts/check-env.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$problems = @()

Write-Host "==> Checking environment for Python development" -ForegroundColor Cyan

# Required: uv (build/test/lint/format driver). It bootstraps the pinned Python
# itself, so no separate `python` is needed on PATH.
if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-Host "    $(uv --version)" -ForegroundColor DarkGray
} else {
    $problems += "the uv toolchain ('uv' is not on PATH)"
}

# Soft: git drives init's author/email defaults and the VCS workflow, but is not
# required to build.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "    note: git is not on PATH — init falls back to placeholder author/email." -ForegroundColor DarkGray
}

if ($problems.Count -eq 0) {
    Write-Host ""
    Write-Host "Environment ready. Next: pwsh ./scripts/init.ps1 -ProjectName ..." -ForegroundColor Green
    Write-Host "(uv installs the pinned Python from .python-version on the first 'uv run'.)" -ForegroundColor DarkGray
    exit 0
}

Write-Host ""
Write-Host "Environment NOT ready. Missing:" -ForegroundColor Red
foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Red }
Write-Host ""
Write-Host "Install uv, then re-run this check:" -ForegroundColor Yellow
Write-Host "  Windows : winget install --id=astral-sh.uv -e   (or: irm https://astral.sh/uv/install.ps1 | iex)"
Write-Host "  macOS   : brew install uv                        (or: curl -LsSf https://astral.sh/uv/install.sh | sh)"
Write-Host "  Linux   : curl -LsSf https://astral.sh/uv/install.sh | sh"
Write-Host "  (any OS) : see https://docs.astral.sh/uv/getting-started/installation/"
exit 1
