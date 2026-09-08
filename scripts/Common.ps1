# Shared helpers for build.ps1, publish.ps1, static-check.ps1 and normalize-eol.ps1.
# Dot-source with: . (Join-Path $PSScriptRoot "Common.ps1")

# Windows PowerShell 5.1 turns redirected native stderr into terminating errors under
# $ErrorActionPreference = "Stop", so native tools run with Continue and are judged by exit code.
# StdOut and StdErr stay separate (trimmed, blank lines dropped). Lines is StdOut, or both streams
# in arrival order when -MergeStdErr is given; Text joins Lines with newlines.
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$MergeStdErr
    )

    if (-not (Get-Command $FilePath -ErrorAction SilentlyContinue)) {
        throw "Executable not found: $FilePath"
    }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # git and gh emit UTF-8; Windows PowerShell would otherwise decode it with the OEM code page.
    # Hosts without a console (ISE, detached processes) cannot change the encoding; keep theirs.
    $previousEncoding = $null
    try {
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    } catch {
        $previousEncoding = $null
    }
    try {
        $stdout = [Collections.Generic.List[string]]::new()
        $stderr = [Collections.Generic.List[string]]::new()
        $all = [Collections.Generic.List[string]]::new()
        $global:LASTEXITCODE = 0
        & $FilePath @Arguments 2>&1 | ForEach-Object {
            $text = ([string]$_).Trim()
            if (-not $text) {
                return
            }
            $all.Add($text)
            if ($_ -is [Management.Automation.ErrorRecord]) {
                $stderr.Add($text)
            } else {
                $stdout.Add($text)
            }
        }
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -ne $previousEncoding) {
            try { [Console]::OutputEncoding = $previousEncoding } catch { }
        }
        $ErrorActionPreference = $previousPreference
    }
    $lines = if ($MergeStdErr) { $all.ToArray() } else { $stdout.ToArray() }
    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = $stdout.ToArray()
        StdErr   = $stderr.ToArray()
        Lines    = @($lines)
        Text     = (@($lines) -join "`n")
    }
}

# Runs a tool, echoes its output (unless -Quiet), and throws "$Description failed ..." (plus
# $FailureHint when given) on a non-zero exit.
function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$Description = "Command",
        [string]$FailureHint = "",
        [switch]$Quiet
    )

    $result = Invoke-Native $FilePath $Arguments -MergeStdErr
    if (-not $Quiet) {
        $result.Lines | ForEach-Object { Write-Host "  $_" }
    }
    if ($result.ExitCode -ne 0) {
        $message = "$Description failed with exit code $($result.ExitCode). $($result.Text)"
        if ($FailureHint) {
            $message = "$message $FailureHint"
        }
        throw $message
    }
    return $result
}

# APP_VERSION from the main source, given either its path or its already-read text.
function Get-AppVersion {
    param([string]$SourcePath = "", [string]$SourceText = "")

    if (-not $SourceText) {
        $SourceText = Get-Content -Raw -LiteralPath $SourcePath
    }
    if ($SourceText -notmatch 'global APP_VERSION\s*:=\s*"([^"]+)"') {
        throw "Could not find APP_VERSION in $(if ($SourcePath) { $SourcePath } else { 'the application source' })"
    }
    return $Matches[1]
}

# The ;@Ahk2Exe-SetVersion directive value (the compiled file version), from path or text.
function Get-Ahk2ExeFileVersion {
    param([string]$SourcePath = "", [string]$SourceText = "")

    if (-not $SourceText) {
        $SourceText = Get-Content -Raw -LiteralPath $SourcePath
    }
    if ($SourceText -notmatch '(?m)^;@Ahk2Exe-SetVersion\s+(\S+)') {
        throw "Could not find the ;@Ahk2Exe-SetVersion directive in $(if ($SourcePath) { $SourcePath } else { 'the application source' })"
    }
    return $Matches[1]
}

# Paths of the provenance files build.ps1 writes next to the artifacts and publish.ps1 uploads.
function Get-BuildOutputPaths {
    param([Parameter(Mandatory = $true)][string]$OutputRoot)

    return [pscustomobject]@{
        Manifest  = Join-Path $OutputRoot "build-manifest.json"
        Checksums = Join-Path $OutputRoot "SHA256SUMS.txt"
    }
}

# Resolves a path against the repository root unless it is already rooted.
function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

# Normalizes a SHA-1 certificate thumbprint (separators removed, upper case); "" when not configured.
function ConvertTo-CertificateThumbprint {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    $normalized = ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($normalized.Length -ne 40) {
        throw "A certificate thumbprint must be 40 hexadecimal digits (SHA-1); got '$Value'."
    }
    return $normalized
}

# Cached by Test-GitAvailable (declared up front because callers run under Set-StrictMode).
$script:gitAvailable = $null

function Test-GitAvailable {
    if ($null -eq $script:gitAvailable) {
        $script:gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
    }
    return $script:gitAvailable
}

# Runs git against $RepoRoot with non-ASCII paths printed verbatim (core.quotePath=false), so every
# caller parses the same path spelling. -Checked throws on a non-zero exit (like Invoke-NativeChecked).
function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$Checked
    )

    $fullArguments = @("-C", $RepoRoot, "-c", "core.quotePath=false") + $Arguments
    if ($Checked) {
        return Invoke-NativeChecked git $fullArguments "git $($Arguments[0])" -Quiet
    }
    return Invoke-Native git $fullArguments
}

# HEAD commit hash, or $null when git is unavailable or the query fails.
function Get-GitHeadCommit {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    if (-not (Test-GitAvailable)) {
        return $null
    }
    $query = Invoke-Git $RepoRoot @("rev-parse", "HEAD")
    if ($query.ExitCode -ne 0 -or $query.StdOut.Count -eq 0 -or $query.StdOut[0] -notmatch '^[0-9a-f]{40}$') {
        return $null
    }
    return $query.StdOut[0]
}

# $true when the working tree has uncommitted changes, $false when clean, $null when unknown.
function Test-GitWorkingTreeDirty {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    if (-not (Test-GitAvailable)) {
        return $null
    }
    $query = Invoke-Git $RepoRoot @("status", "--porcelain")
    if ($query.ExitCode -ne 0) {
        return $null
    }
    return ($query.StdOut.Count -gt 0)
}

# Full path of the working tree that contains $RepoRoot; throws (with git's message) when git cannot
# answer, so "not a git repository" and a broken repository are both reported, never guessed.
function Get-GitTopLevel {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $query = Invoke-Git $RepoRoot @("rev-parse", "--show-toplevel")
    if ($query.ExitCode -ne 0 -or $query.StdOut.Count -eq 0) {
        throw "git rev-parse --show-toplevel failed for ${RepoRoot}: $($query.StdErr -join ' ')"
    }
    return [IO.Path]::GetFullPath($query.StdOut[0])
}

# Parses `git ls-files --eol` into objects with Index, Worktree, Attr and Path. git leaves the i/ or
# w/ field empty for symlinks and for paths missing from the worktree, so both may be "".
function Get-GitEolEntries {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string[]]$Path = @()
    )

    $arguments = @("ls-files", "--eol")
    if ($Path.Count -gt 0) {
        $arguments += @("--") + $Path
    }
    $query = Invoke-Git $RepoRoot $arguments
    if ($query.ExitCode -ne 0) {
        throw "git ls-files --eol failed: $($query.StdErr -join ' ')"
    }
    foreach ($line in $query.StdOut) {
        if ($line -match '^i/(\S*)\s+w/(\S*)\s+attr/([^\t]*)\t(.+)$') {
            [pscustomobject]@{ Index = $Matches[1]; Worktree = $Matches[2]; Attr = $Matches[3]; Path = $Matches[4] }
        }
    }
}

# Text files (attr text / text=auto) whose committed blob is not LF, or whose checkout is not LF while
# the attributes ask for LF (a per-path eol=crlf override is honored).
function Get-UnnormalizedTextEolEntries {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string[]]$Path = @()
    )

    @(Get-GitEolEntries $RepoRoot -Path $Path | Where-Object {
        $_.Attr -match '^text\b' -and (
            $_.Index -in @("crlf", "mixed") -or
            ($_.Worktree -in @("crlf", "mixed") -and $_.Attr -match '\beol=lf\b')
        )
    })
}
