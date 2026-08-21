#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initializes this template into a concrete Python project.

.DESCRIPTION
    POSIX counterpart: scripts/init.sh — use whichever matches your shell.

    Replaces the placeholder tokens in file contents AND in file/folder names,
    then removes the template-only files (TEMPLATE.md, docs/AGENT-INIT-GUIDE.md,
    and — unless -KeepScript — both initializers, init.ps1 and init.sh).

    Two name tokens are stamped:
      __ProjectName__  the PyPI distribution / repo name, used verbatim (e.g.
                       "acme-widgets"). Goes into pyproject `name`, URLs, LICENSE.
      __PackageName__  the importable package, DERIVED from the project name
                       (lowercased, runs of non-alphanumerics -> '_', leading '_'
                       added if it would start with a digit) — e.g. "Acme.Widgets"
                       -> "acme_widgets". Names the src/ package dir and imports.

    Run it once, right after creating a repository from the template:

        pwsh ./scripts/init.ps1 -ProjectName acme-widgets

.PARAMETER ProjectName
    PyPI distribution / repo name. Required. Used verbatim for the distribution
    name and URLs; the importable package name is derived from it.

.PARAMETER Author
    Author for LICENSE and package metadata. Defaults to `git config user.name`, else "Your Name".

.PARAMETER AuthorEmail
    Author email for package metadata and the release commit. Defaults to `git config user.email`, else "you@example.com".

.PARAMETER GitHubOwner
    GitHub owner/org used in repository URLs. Defaults to "your-org".

.PARAMETER Description
    Short package description. Defaults to "TODO: project description".

.PARAMETER Year
    Copyright year. Defaults to the current year.

.PARAMETER KeepScript
    Keep both initializers (init.ps1 and init.sh) after running. TEMPLATE.md and
    docs/AGENT-INIT-GUIDE.md are removed either way.

.EXAMPLE
    pwsh ./scripts/init.ps1 -ProjectName acme-widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    [string]$Author,
    [string]$AuthorEmail,
    [string]$GitHubOwner,
    [string]$Description,
    [int]$Year = (Get-Date).Year,
    [switch]$KeepScript
)

$ErrorActionPreference = 'Stop'

# Validate as a PEP 503 distribution name: ASCII letters, digits, '.', '-', '_',
# starting and ending with an alphanumeric. PyPI normalizes case and separators,
# but an out-of-set character (space, '/', '!', ...) would produce an invalid
# pyproject `name` that won't build — reject it here with a clear message.
if ($ProjectName -notmatch '^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$') {
    throw "Invalid -ProjectName '$ProjectName'. Use ASCII letters, digits, '.', '-', '_'; it must start and end with a letter or digit (e.g. acme-widgets)."
}

# Derive the importable package name: lowercase, collapse runs of non-alphanumerics
# to '_', trim leading/trailing '_'.
$packageName = ($ProjectName.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
if (-not $packageName) {
    throw "Invalid -ProjectName '$ProjectName'. It must contain at least one ASCII letter or digit so a Python package name can be derived (e.g. acme-widgets)."
}
# A Python identifier cannot start with a digit; prefix '_' so the package stays importable.
if ($packageName -match '^[0-9]') { $packageName = "_$packageName" }

if (-not $Author) {
    $Author = (& git config user.name 2>$null)
    if (-not $Author) { $Author = 'Your Name' }
}
if (-not $AuthorEmail) {
    $AuthorEmail = (& git config user.email 2>$null)
    if (-not $AuthorEmail) { $AuthorEmail = 'you@example.com' }
}
if (-not $GitHubOwner) { $GitHubOwner = 'your-org' }
if (-not $Description) { $Description = 'TODO: project description' }
if ($Year -lt 0) {
    throw "Invalid -Year '$Year'. Use a non-negative number."
}

# These values are copied into TOML, Markdown, YAML block scalars, and shell
# source. Reject characters that could change any of those contexts before the
# first file is touched. Safe values are kept verbatim in every target format.
$unsafeMetadataChars = [char[]]@('"', "'", '\', '$', '`', ';', '&', '|', '<', '>')
function Assert-SafeMetadata([string]$parameterName, [string]$value) {
    if ($value -match '[\x00-\x1F\x7F]' -or $value.IndexOfAny($unsafeMetadataChars) -ge 0) {
        throw "Invalid $parameterName. The value contains a control character, quote, backslash, or shell operator; these values are unsafe in generated TOML/YAML/Markdown/shell contexts."
    }
}

Assert-SafeMetadata '-Author' $Author
Assert-SafeMetadata '-AuthorEmail' $AuthorEmail
Assert-SafeMetadata '-GitHubOwner' $GitHubOwner
Assert-SafeMetadata '-Description' $Description
if ($GitHubOwner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$') {
    throw "Invalid -GitHubOwner '$GitHubOwner'. Use a GitHub owner name of 1-39 letters, digits, or internal hyphens."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$selfPath = $PSCommandPath

$replacements = [ordered]@{
    '__ProjectName__' = $ProjectName
    '__PackageName__' = $packageName
    '__Author__'      = $Author
    '__AuthorEmail__' = $AuthorEmail
    '__GitHubOwner__' = $GitHubOwner
    '__Description__' = $Description
    '__Year__'        = "$Year"
}

# Keep TOML escaping defensive even though the metadata preflight above rejects
# quotes and backslashes. The derived package name is [a-z0-9_] only, so it is safe.
$tomlReplacements = [ordered]@{}
foreach ($key in $replacements.Keys) {
    $tomlReplacements[$key] = $replacements[$key].Replace('\', '\\').Replace('"', '\"')
}
$tomlFileExtensions = @('.toml')

$excludedDirs = @('.git', '.jj', '.venv', 'dist', 'build', '__pycache__')

function Test-Excluded([string]$fullPath) {
    $rel = $fullPath.Substring($repoRoot.Length).TrimStart('\', '/')
    foreach ($seg in ($rel -split '[\\/]')) {
        if ($excludedDirs -contains $seg) { return $true }
    }
    return $false
}

Write-Host "==> Initializing template as '$ProjectName' (package '$packageName')" -ForegroundColor Cyan

# 1) Replace tokens in file contents. Both initializers are skipped: they carry
#    the literal token strings as search keys, so substituting inside them would
#    corrupt the sibling script.
$siblingSh = Join-Path $PSScriptRoot 'init.sh'
$files = Get-ChildItem -Path $repoRoot -File -Recurse | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.FullName -ne $selfPath -and $_.FullName -ne $siblingSh
}
$contentChanged = 0
foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $new = $text
    $map = if ($tomlFileExtensions -contains $file.Extension) { $tomlReplacements } else { $replacements }
    foreach ($key in $map.Keys) {
        $new = $new.Replace($key, $map[$key])
    }
    if ($new -ne $text) {
        # UTF-8 without BOM, LF preserved — matches .gitattributes (eol=lf).
        [System.IO.File]::WriteAllText($file.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
        $contentChanged++
    }
}
Write-Host "    Updated contents in $contentChanged file(s)." -ForegroundColor DarkGray

# 2) Rename files and folders whose name contains a name token. Deepest paths
#    first so child renames don't invalidate parent paths. The src package dir
#    (src/__PackageName__) is the main case.
$named = Get-ChildItem -Path $repoRoot -Recurse | Where-Object {
    -not (Test-Excluded $_.FullName) -and ($_.Name -like '*__ProjectName__*' -or $_.Name -like '*__PackageName__*')
} | Sort-Object { $_.FullName.Length } -Descending
foreach ($item in $named) {
    $newName = $item.Name.Replace('__ProjectName__', $ProjectName).Replace('__PackageName__', $packageName)
    Rename-Item -LiteralPath $item.FullName -NewName $newName
    Write-Host "    Renamed $($item.Name) -> $newName" -ForegroundColor DarkGray
}

# 3) Activate the Claude Code shared settings (shipped inert as a .template file).
$claudeTemplate = Join-Path $repoRoot '.claude/settings.json.template'
if (Test-Path $claudeTemplate) {
    Move-Item -LiteralPath $claudeTemplate -Destination (Join-Path $repoRoot '.claude/settings.json') -Force
    Write-Host "    Activated .claude/settings.json" -ForegroundColor DarkGray
}

# 4) Remove template-only files.
$templateOnly = @('TEMPLATE.md', 'docs/AGENT-INIT-GUIDE.md')
foreach ($rel in $templateOnly) {
    $p = Join-Path $repoRoot $rel
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
}
# Drop docs/ if it's now empty.
$docsDir = Join-Path $repoRoot 'docs'
if ((Test-Path $docsDir) -and -not (Get-ChildItem -LiteralPath $docsDir -Force)) {
    Remove-Item -LiteralPath $docsDir -Force
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. uv run pytest"
Write-Host "  2. uv run ruff format --check . && uv run ruff check . && uv run mypy"
Write-Host "  3. Review LICENSE (author/year) and the package metadata in pyproject.toml."
Write-Host "  4. Publishing: add the PYPI_API_TOKEN repo secret, or delete"
Write-Host "     .github/workflows/release.yml and the [project.urls] / packaging metadata."
Write-Host "  5. Replace src/$packageName with your code and delete the sample test, then commit."

# Remove both initializers unless asked to keep them.
if (-not $KeepScript) {
    if (Test-Path $siblingSh) { Remove-Item -LiteralPath $siblingSh -Force }
    Remove-Item -LiteralPath $selfPath -Force
}
