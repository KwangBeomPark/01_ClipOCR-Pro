[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $repoRoot "src\ClipOCR-Pro.ahk"
# Normalize once so every anchored regex below is line-ending agnostic (editors may save CRLF).
$main = (Get-Content -Raw -LiteralPath $mainPath) -replace "`r`n", "`n"
$failures = [Collections.Generic.List[string]]::new()

function Assert-Project {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

foreach ($scriptPath in @(
    (Join-Path $PSScriptRoot "Common.ps1"),
    (Join-Path $PSScriptRoot "normalize-eol.ps1"),
    (Join-Path $PSScriptRoot "build.ps1"),
    (Join-Path $PSScriptRoot "publish.ps1"),
    (Join-Path $PSScriptRoot "Invoke-WindowsOcr.ps1"),
    $PSCommandPath
)) {
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    Assert-Project ($parseErrors.Count -eq 0) "PowerShell syntax errors in $scriptPath"
}

# Line endings are pinned by .gitattributes so CI and local builds hash identically; the policy
# must exist and the checked-out tree must actually be normalized (older clones may still hold CRLF).
$gitAttributesPath = Join-Path $repoRoot ".gitattributes"
$gitAttributes = if (Test-Path -LiteralPath $gitAttributesPath -PathType Leaf) { Get-Content -Raw -LiteralPath $gitAttributesPath } else { "" }
Assert-Project ($gitAttributes -match '(?m)^\*\s+text=auto\s+eol=lf') ".gitattributes must exist and pin '* text=auto eol=lf'."
# Only an exported source archive has no .git entry (clones, worktrees and submodules all do); every
# other git failure, such as dubious ownership, must fail the check rather than skip it.
if (Test-Path -LiteralPath (Join-Path $repoRoot ".git")) {
    # scripts/normalize-eol.ps1 owns the repair; both scripts share the parser in Common.ps1.
    try {
        $unnormalized = @(Get-UnnormalizedTextEolEntries $repoRoot | ForEach-Object { $_.Path })
        Assert-Project ($unnormalized.Count -eq 0) "Tracked text files are not LF-normalized; run scripts/normalize-eol.ps1: $($unnormalized -join ', ')"
    } catch {
        Assert-Project $false "Could not verify line endings: $($_.Exception.Message)"
    }
} else {
    Write-Host "Line-ending check skipped: no .git entry (exported source archives are LF by construction)."
}

$appVersionValue = $null
$fileVersionValue = $null
try {
    $appVersionValue = Get-AppVersion -SourceText $main
} catch {
    $appVersionValue = $null
}
try {
    $fileVersionValue = Get-Ahk2ExeFileVersion -SourceText $main
} catch {
    $fileVersionValue = $null
}
Assert-Project ($null -ne $appVersionValue) "APP_VERSION is missing."
Assert-Project ($null -ne $fileVersionValue) "Ahk2Exe file version is missing."
if ($null -ne $appVersionValue -and $null -ne $fileVersionValue) {
    Assert-Project ($fileVersionValue -eq "$appVersionValue.0") "App and file versions differ."
}

foreach ($include in @("SuiteRegistry.ahk", "OcrService.ahk", "HealthCheck.ahk")) {
    Assert-Project ($main -match "(?m)^#Include $([regex]::Escape($include))$") "Missing module include: $include"
}

$menuNumbers = @([regex]::Matches($main, '(?m)^ClipMenu\.Add\("[^"]*? (\d+)\.') |
    ForEach-Object { [int]$_.Groups[1].Value })
Assert-Project ($menuNumbers.Count -eq 20) "Expected 20 numbered capture-menu commands."
for ($index = 0; $index -lt $menuNumbers.Count; $index++) {
    Assert-Project ($menuNumbers[$index] -eq ($index + 1)) "Capture-menu numbering is out of sequence."
}

foreach ($readOnlyModule in @("SuiteRegistry.ahk", "OcrService.ahk", "HealthCheck.ahk")) {
    $moduleText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "src\$readOnlyModule")
    Assert-Project ($moduleText -notmatch '\bRegWrite\b') "$readOnlyModule must not write Registry values."
}

$ocrText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "src\OcrService.ahk")
$ocrHelperText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "Invoke-WindowsOcr.ps1")
Assert-Project ($ocrText -notmatch 'https?://|GoogleTranslate|EnsureTranslationConsent') "Local OCR service crosses the external-service boundary."
Assert-Project ($ocrHelperText -notmatch 'Invoke-WebRequest|HttpClient|WebClient|https?://') "Windows OCR helper contains network access."
Assert-Project ($main -match 'FileInstall\("\.\.\\scripts\\Invoke-WindowsOcr\.ps1"') "Compiled OCR helper embedding is missing."

# Matches an invocation of $Executable with $Verb in every form the scripts use: a bare command
# (`git push`, `& git -C $root push`) or an argument array (`Invoke-Native git @("push", ...)`,
# `git ($base + @("-C", $root, "push"))`). The executable must sit where a command can start (line
# start, after an operator, or as the tool passed to Invoke-Native), so prose in strings or comments
# such as "commit them" never matches.
function Get-NativeCallPattern {
    param([string]$Executable, [string]$Verb)

    $token = '(?:^|[=(&|;{]|Invoke-Native(?:Checked)?)\s*' + $Executable + '(?:\.exe)?'
    $bare = '(?:\s+[^\s"''()@;|&#]+)*?\s+' + $Verb + '(?![\w-])'
    $array = '\s+\(?\s*(?:\$\w+\s*\+\s*)?@\(\s*(?:(?:"[^"]*"|''[^'']*''|\$[\w.]+)\s*,\s*)*?["'']' + $Verb + '["'']'
    return "(?im)$token(?:$bare|$array)"
}

$buildText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "build.ps1")
$publishText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "publish.ps1")
Assert-Project ($buildText -notmatch (Get-NativeCallPattern 'git' 'push')) "Build script must not push."
Assert-Project ($buildText -notmatch '(?im)(?:^|[=(&|;{]|Invoke-Native(?:Checked)?)\s*gh(?:\.exe)?(?:\s|$)') "Build script must not invoke gh."
Assert-Project ($publishText -notmatch (Get-NativeCallPattern 'git' '(?:commit|add)')) "Publish script must not create commits."
Assert-Project (Test-Path -LiteralPath (Join-Path $repoRoot "docs\OCR_PACKAGING.md") -PathType Leaf) "OCR deployment guide is missing."

if ($failures.Count -gt 0) {
    # Write-Error would become terminating under $ErrorActionPreference = "Stop" and hide the rest.
    foreach ($failure in $failures) {
        [Console]::Error.WriteLine("FAIL: $failure")
    }
    exit 1
}

Write-Host "ClipOCR-Pro static checks: PASS"
