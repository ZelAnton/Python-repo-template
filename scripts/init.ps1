#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initializes this template into a concrete Python project.

.DESCRIPTION
    POSIX counterpart: scripts/init.sh. Replaces template tokens in file
    contents and names, activates shared settings, and removes template-only
    files. The complete transformation is staged before the checkout changes.
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

if ($ProjectName -notmatch '^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$') {
    throw "Invalid -ProjectName '$ProjectName'. Use ASCII letters, digits, '.', '-', '_'; it must start and end with a letter or digit (e.g. acme-widgets)."
}

$packageName = ($ProjectName.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
if (-not $packageName) {
    throw "Invalid -ProjectName '$ProjectName'. It must contain at least one ASCII letter or digit so a Python package name can be derived."
}
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
$unsafeUnicodePattern = '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]'
$markdownUnsafeChars = [char[]]@('[', ']', '(', ')', '#', '*', '_', '~')
# Description is a standalone README paragraph; reject Markdown block starters
# before any template file is changed.
$markdownBlockPattern = '(^[\t ]{4}|^[\t ]{0,3}(?:[-+*][\t ]+.*|[0-9]{1,9}[.)][\t ]+.*|[-+*]|[0-9]{1,9}[.)]|(?:-[\t ]*){3,}|(?:_[\t ]*){3,}|(?:\*[\t ]*){3,})$)'
function Assert-SafeMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParameterName,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$RejectMarkdownSyntax
    )

    if ($Value -match $unsafeUnicodePattern -or $Value.IndexOfAny($unsafeMetadataChars) -ge 0) {
        throw "Invalid $ParameterName. The value contains a control character, quote, backslash, or shell operator; these values are unsafe in generated TOML/YAML/Markdown/shell contexts."
    }
    if ($RejectMarkdownSyntax -and ($Value.IndexOfAny($markdownUnsafeChars) -ge 0 -or $Value -match $markdownBlockPattern)) {
        throw "Invalid $ParameterName. The value contains unsafe Markdown control syntax; use plain text for the generated README description."
    }
}

Assert-SafeMetadata '-Author' $Author
Assert-SafeMetadata '-AuthorEmail' $AuthorEmail
Assert-SafeMetadata '-GitHubOwner' $GitHubOwner
Assert-SafeMetadata '-Description' $Description -RejectMarkdownSyntax
if ($GitHubOwner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$') {
    throw "Invalid -GitHubOwner '$GitHubOwner'. Use a GitHub owner name of 1-39 letters, digits, or internal hyphens."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$selfPath = $PSCommandPath
$siblingSh = Join-Path $PSScriptRoot 'init.sh'
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
    foreach ($segment in ($fullPath -split '[\\/]')) {
        if ($excludedDirs -contains $segment) { return $true }
    }
    return $false
}

function Get-PathKey([string]$path) {
    return [System.IO.Path]::GetFullPath($path).ToLowerInvariant()
}

function Assert-DirectoryWritable([string]$directory, [string]$operation) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Preflight cannot $operation directory '$directory': it is missing."
    }
    $item = Get-Item -LiteralPath $directory -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
        throw "Preflight cannot $operation directory '$directory': it is read-only."
    }
    $probe = Join-Path $directory ".init-preflight-$([guid]::NewGuid().ToString('N'))"
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($probe, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Dispose()
        $stream = $null
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    } catch {
        if ($stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $probe) {
            try { Remove-Item -LiteralPath $probe -Force -ErrorAction Stop } catch {
                throw "Preflight cannot $operation directory '$directory': permission probe '$probe' could not be removed: $($_.Exception.Message)"
            }
        }
        throw "Preflight cannot $operation directory '$directory': $($_.Exception.Message)"
    }
}

function Assert-WritablePath([string]$path, [string]$operation) {
    $exists = Test-Path -LiteralPath $path
    if ($exists) {
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            throw "Preflight cannot $operation '$path': it is read-only."
        }
    }
    $parent = Split-Path -Path $path -Parent
    Assert-DirectoryWritable $parent $operation
    if ($exists -and $item.PSIsContainer) {
        Assert-DirectoryWritable $path $operation
    }
}

function Copy-MutableTree([string]$sourceRoot, [string]$destinationRoot) {
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $sourceRoot -Force)) {
        if ($item.Name -eq '.git' -or (Test-Excluded $item.FullName)) { continue }
        $destination = Join-Path $destinationRoot $item.Name
        if ($item.PSIsContainer) {
            Copy-MutableTree $item.FullName $destination
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
        }
    }
}

function Remove-MutableTree([string]$root) {
    foreach ($item in (Get-ChildItem -LiteralPath $root -Force)) {
        if ($item.Name -eq '.git' -or (Test-Excluded $item.FullName)) { continue }
        if ($item.PSIsContainer) {
            Remove-MutableTree $item.FullName
            if (-not (Get-ChildItem -LiteralPath $item.FullName -Force)) {
                Remove-Item -LiteralPath $item.FullName -Force
            }
        } else {
            Remove-Item -LiteralPath $item.FullName -Force
        }
    }
}

function Invoke-FailureInjection([string]$boundary) {
    if ($env:TEMPLATE_INIT_FAIL_AT -eq $boundary) {
        throw "Injected failure at '$boundary'."
    }
}

function Write-StagedFileAtomically([string]$source, [string]$destination, [string]$transactionId) {
    $parent = Split-Path -Path $destination -Parent
    $temporary = Join-Path $parent ".init-$transactionId-$([System.IO.Path]::GetRandomFileName())"
    try {
        Copy-Item -LiteralPath $source -Destination $temporary -Force
        Move-Item -LiteralPath $temporary -Destination $destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction Stop
        }
    }
}

$claudeTemplate = Join-Path $repoRoot '.claude/settings.json.template'
$claudeSettings = Join-Path $repoRoot '.claude/settings.json'
$templateOnly = @('TEMPLATE.md', 'docs/AGENT-INIT-GUIDE.md')
$docsDir = Join-Path $repoRoot 'docs'
$renamePlans = [System.Collections.Generic.List[object]]::new()
$contentPlans = [System.Collections.Generic.List[object]]::new()
$transactionRoot = $null
$transactionStarted = $false
$cleanupFailureInjected = $false

function Remove-TransactionRoot([string]$path) {
    if ($env:TEMPLATE_INIT_FAIL_AT -eq 'cleanup' -and -not $script:cleanupFailureInjected) {
        $script:cleanupFailureInjected = $true
        throw "Injected failure at 'cleanup'."
    }
    if ($path -and (Test-Path -LiteralPath $path)) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    }
    if ($path -and (Test-Path -LiteralPath $path)) {
        throw "Transaction cleanup did not remove staging directory '$path'."
    }
}

Write-Host "==> Initializing template as '$ProjectName' (package '$packageName')" -ForegroundColor Cyan

try {
    # Read and validate every input before creating staging or changing the checkout.
    $files = Get-ChildItem -Path $repoRoot -File -Recurse -Force | Where-Object {
        -not (Test-Excluded $_.FullName) -and $_.FullName -ne $selfPath -and $_.FullName -ne $siblingSh
    }
    foreach ($file in $files) {
        try { $text = [System.IO.File]::ReadAllText($file.FullName) }
        catch { throw "Preflight cannot read '$($file.FullName)': $($_.Exception.Message)" }
        $new = $text
        $map = if ($tomlFileExtensions -contains $file.Extension) { $tomlReplacements } else { $replacements }
        foreach ($key in $map.Keys) { $new = $new.Replace($key, $map[$key]) }
        if ($new -ne $text) {
            Assert-WritablePath $file.FullName 'write'
            $contentPlans.Add([pscustomobject]@{
                    RelativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
                    Content      = $new
                })
        }
    }

    $named = Get-ChildItem -Path $repoRoot -Recurse -Force | Where-Object {
        -not (Test-Excluded $_.FullName) -and ($_.Name -like '*__ProjectName__*' -or $_.Name -like '*__PackageName__*')
    } | Sort-Object { $_.FullName.Length } -Descending
    $renameSources = @{}
    $renameTargets = @{}
    foreach ($item in $named) {
        $newName = $item.Name.Replace('__ProjectName__', $ProjectName).Replace('__PackageName__', $packageName)
        $target = Join-Path (Split-Path -Path $item.FullName -Parent) $newName
        $sourceKey = Get-PathKey $item.FullName
        $targetKey = Get-PathKey $target
        if ($targetKey -eq $sourceKey) { continue }
        if ($renameTargets.ContainsKey($targetKey)) {
            throw "Preflight rename conflict: '$($item.FullName)' and '$($renameTargets[$targetKey])' both target '$target'."
        }
        $renameSources[$sourceKey] = $true
        $renameTargets[$targetKey] = $item.FullName
        $renamePlans.Add([pscustomobject]@{ Source = $item.FullName; NewName = $newName; Target = $target; OldName = $item.Name })
    }
    foreach ($plan in $renamePlans) {
        $targetKey = Get-PathKey $plan.Target
        if ((Test-Path -LiteralPath $plan.Target) -and -not $renameSources.ContainsKey($targetKey)) {
            throw "Preflight rename conflict: target '$($plan.Target)' already exists."
        }
        if (-not (Test-Path -LiteralPath (Split-Path -Path $plan.Target -Parent) -PathType Container)) {
            throw "Preflight cannot rename '$($plan.Source)': target directory is missing."
        }
        Assert-WritablePath $plan.Source 'rename'
        Assert-WritablePath $plan.Target 'rename'
    }

    if (Test-Path -LiteralPath $claudeTemplate) {
        if (Test-Path -LiteralPath $claudeSettings) {
            throw "Preflight settings conflict: both '$claudeTemplate' and '$claudeSettings' exist."
        }
        Assert-WritablePath $claudeTemplate 'activate settings'
        Assert-WritablePath $claudeSettings 'activate settings'
    }
    foreach ($relativePath in $templateOnly) {
        $path = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $path) { Assert-WritablePath $path 'remove' }
    }
    if (Test-Path -LiteralPath $docsDir) { Assert-WritablePath $docsDir 'remove' }
    if (-not $KeepScript) {
        if (Test-Path -LiteralPath $siblingSh) { Assert-WritablePath $siblingSh 'remove' }
        Assert-WritablePath $selfPath 'remove'
    }

    $transactionId = [guid]::NewGuid().ToString('N')
    $transactionRoot = Join-Path ([System.IO.Path]::GetTempPath()) "python-template-init-$transactionId"
    $candidateRoot = Join-Path $transactionRoot 'candidate'
    $contentRoot = Join-Path $transactionRoot 'content'
    $rollbackRoot = Join-Path $transactionRoot 'rollback'
    New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
    Copy-MutableTree $repoRoot $candidateRoot

    foreach ($plan in $contentPlans) {
        $candidatePath = Join-Path $candidateRoot $plan.RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Path $candidatePath -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($candidatePath, $plan.Content, (New-Object System.Text.UTF8Encoding($false)))
        $contentPath = Join-Path $contentRoot $plan.RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Path $contentPath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $candidatePath -Destination $contentPath -Force
    }
    Invoke-FailureInjection 'content-write'

    foreach ($plan in $renamePlans) {
        $candidatePath = Join-Path $candidateRoot ($plan.Source.Substring($repoRoot.Length).TrimStart('\', '/'))
        Rename-Item -LiteralPath $candidatePath -NewName $plan.NewName
    }
    Invoke-FailureInjection 'path-rename'
    $candidateSettingsTemplate = Join-Path $candidateRoot '.claude/settings.json.template'
    if (Test-Path -LiteralPath $candidateSettingsTemplate) {
        Move-Item -LiteralPath $candidateSettingsTemplate -Destination (Join-Path $candidateRoot '.claude/settings.json')
    }
    Invoke-FailureInjection 'settings-activation'
    foreach ($relativePath in $templateOnly) {
        $path = Join-Path $candidateRoot $relativePath
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    $candidateDocs = Join-Path $candidateRoot 'docs'
    if ((Test-Path -LiteralPath $candidateDocs) -and -not (Get-ChildItem -LiteralPath $candidateDocs -Force)) {
        Remove-Item -LiteralPath $candidateDocs -Force
    }
    if (-not $KeepScript) {
        Remove-Item -LiteralPath (Join-Path $candidateRoot 'scripts/init.ps1') -Force
        Remove-Item -LiteralPath (Join-Path $candidateRoot 'scripts/init.sh') -Force
    }
    Invoke-FailureInjection 'template-removal'

    # Snapshot immediately before the first checkout write.
    Copy-MutableTree $repoRoot $rollbackRoot
    $transactionStarted = $true
    Invoke-FailureInjection 'apply-content-write'
    foreach ($plan in $contentPlans) {
        Write-StagedFileAtomically (Join-Path $contentRoot $plan.RelativePath) (Join-Path $repoRoot $plan.RelativePath) $transactionId
    }
    Invoke-FailureInjection 'apply-path-rename'
    foreach ($plan in $renamePlans) {
        Rename-Item -LiteralPath $plan.Source -NewName $plan.NewName
        Write-Host "    Renamed $($plan.OldName) -> $($plan.NewName)" -ForegroundColor DarkGray
    }
    Invoke-FailureInjection 'apply-settings-activation'
    if (Test-Path -LiteralPath $claudeTemplate) {
        Move-Item -LiteralPath $claudeTemplate -Destination $claudeSettings
        Write-Host "    Activated .claude/settings.json" -ForegroundColor DarkGray
    }
    Invoke-FailureInjection 'apply-template-removal'
    foreach ($relativePath in $templateOnly) {
        $path = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $docsDir) -and -not (Get-ChildItem -LiteralPath $docsDir -Force)) {
        Remove-Item -LiteralPath $docsDir -Force
    }
    if (-not $KeepScript) {
        if (Test-Path -LiteralPath $siblingSh) { Remove-Item -LiteralPath $siblingSh -Force }
        Remove-Item -LiteralPath $selfPath -Force
    }
    Remove-TransactionRoot $transactionRoot
    $transactionStarted = $false
    $transactionRoot = $null
} catch {
    $message = $_.Exception.Message
    $location = $_.InvocationInfo.PositionMessage
    $rollbackMessage = $null
    $cleanupMessage = $null
    if ($transactionStarted) {
        try {
            Remove-MutableTree $repoRoot
            Copy-MutableTree $rollbackRoot $repoRoot
        } catch {
            $rollbackMessage = $_.Exception.Message
        }
    }
    if ($transactionRoot -and (Test-Path -LiteralPath $transactionRoot)) {
        try { Remove-TransactionRoot $transactionRoot } catch { $cleanupMessage = $_.Exception.Message }
    }
    if ($rollbackMessage -and $cleanupMessage) {
        throw "Initialization failed: $message at $location Rollback failed: $rollbackMessage Cleanup failed: $cleanupMessage Staging artifact: $transactionRoot"
    }
    if ($rollbackMessage) { throw "Initialization failed: $message at $location Rollback failed: $rollbackMessage" }
    if ($cleanupMessage) { throw "Initialization failed: $message at $location Cleanup failed: $cleanupMessage Staging artifact: $transactionRoot" }
    throw "Initialization failed: $message at $location"
}

Write-Host "    Updated contents in $($contentPlans.Count) file(s)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. uv run pytest"
Write-Host "  2. uv run ruff format --check . && uv run ruff check . && uv run mypy"
Write-Host "  3. Review LICENSE (author/year) and the package metadata in pyproject.toml."
Write-Host "  4. Publishing: add the PYPI_API_TOKEN repo secret, or delete"
Write-Host "     .github/workflows/release.yml and the [project.urls] / packaging metadata."
Write-Host "  5. Replace src/$packageName with your code and delete the sample test, then commit."
