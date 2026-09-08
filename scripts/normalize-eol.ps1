[CmdletBinding()]
param()

# Brings the working tree in line with the LF policy in .gitattributes:
# - committed CRLF blobs are renormalized in the index (you then commit them);
# - CRLF checkouts of LF blobs are rewritten: `git checkout-index --temp` writes each index blob
#   through git's own worktree conversion to a temporary file, which is then moved into place.
#   git cannot write the tracked path itself (`checkout`, `checkout-index -f`, `restore`) because it
#   treats a CRLF checkout of an LF blob as clean and skips it.
# Files with real unstaged edits (line-ending-only differences ignored) and entries pinned with
# skip-worktree / assume-unchanged are listed and left alone.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-GitAvailable)) {
    throw "git is required to normalize line endings."
}
# checkout-index writes its temporary files at the top level of the working tree, which must
# therefore be this project (a copy nested inside another repository is refused, not guessed at).
$topLevel = Get-GitTopLevel $repoRoot
if ($topLevel.TrimEnd('\') -ne ([IO.Path]::GetFullPath($repoRoot)).TrimEnd('\')) {
    throw "$repoRoot is not the top level of its git working tree ($topLevel); run this script from a clone of the project."
}

$entries = @(Get-UnnormalizedTextEolEntries $repoRoot)
if ($entries.Count -eq 0) {
    Write-Host "All tracked text files are already LF-normalized."
    return
}
$candidatePaths = @($entries | ForEach-Object { $_.Path })

$dirty = @((Invoke-Git $repoRoot (@("diff", "--ignore-cr-at-eol", "--name-only", "--") + $candidatePaths) -Checked).StdOut)
# `ls-files -v` tags skip-worktree entries with S and assume-unchanged entries with a lowercase letter.
$pinned = @((Invoke-Git $repoRoot (@("ls-files", "-v", "--") + $candidatePaths) -Checked).StdOut |
    Where-Object { $_ -cmatch '^[Sa-z] ' } | ForEach-Object { $_.Substring(2) })
$skipped = @($candidatePaths | Where-Object { $dirty -contains $_ -or $pinned -contains $_ })
$workable = @($entries | Where-Object { $skipped -notcontains $_.Path })

# 1. Committed CRLF blobs: renormalize in the index (after this every workable index blob is LF).
$indexPaths = @($workable | Where-Object { $_.Index -in @("crlf", "mixed") } | ForEach-Object { $_.Path })
if ($indexPaths.Count -gt 0) {
    $null = Invoke-Git $repoRoot (@("add", "--renormalize", "--") + $indexPaths) -Checked
    Write-Host "Renormalized $($indexPaths.Count) committed CRLF file(s) in the index; commit them: $($indexPaths -join ', ')"
}

# 2. CRLF checkouts: let git write each index blob (with worktree conversion) to a temporary file.
$rewritePaths = @($workable | Where-Object { $_.Worktree -in @("crlf", "mixed") } | ForEach-Object { $_.Path })
$rewritten = 0
if ($rewritePaths.Count -gt 0) {
    $listing = Invoke-Git $repoRoot (@("checkout-index", "--temp", "--") + $rewritePaths) -Checked
    foreach ($line in $listing.StdOut) {
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) {
            continue
        }
        $temporary = Join-Path $repoRoot $parts[0]
        try {
            Move-Item -LiteralPath $temporary -Destination (Join-Path $repoRoot $parts[1]) -Force
            $rewritten++
        } catch {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            Write-Warning "Could not replace $($parts[1]): $($_.Exception.Message)"
        }
    }
    Write-Host "Rewrote $rewritten of $($rewritePaths.Count) CRLF checkout(s) with LF from the index."
}

$problems = @()
if ($skipped.Count -gt 0) {
    $problems += "Skipped file(s) with unstaged edits or a skip-worktree/assume-unchanged flag; commit, stash or unpin them, then rerun: $($skipped -join ', ')"
}
$remaining = @(Get-UnnormalizedTextEolEntries $repoRoot -Path $candidatePaths | Where-Object { $skipped -notcontains $_.Path })
if ($remaining.Count -gt 0) {
    $problems += "Still not normalized: $(($remaining | ForEach-Object { $_.Path }) -join ', ')"
}
if ($problems.Count -gt 0) {
    throw ($problems -join "`n")
}
Write-Host "All tracked text files are now LF-normalized."
