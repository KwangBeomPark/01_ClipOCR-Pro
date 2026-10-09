[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
param(
    [string]$OutputDirectory = "release",
    [switch]$AllowUnsigned,
    [switch]$AllowLegacyTimestamp,
    [switch]$NoPush,
    [switch]$Draft
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")
. (Join-Path $PSScriptRoot "ReleaseSafety.ps1")
if ($AllowUnsigned -or $AllowLegacyTimestamp) { throw 'Unsigned and legacy timestamp waivers are development-only; official publication cannot bypass verification.' }

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\ClipOCR-Pro.ahk"
$version = Get-AppVersion $sourcePath
$tag = "v$version"
$officialOutput = Resolve-RepoPath $repoRoot $OutputDirectory
if ($officialOutput -ne (Join-Path $repoRoot 'release')) { throw 'Official publication uses the repository release directory; development builds belong in dist/build.' }

foreach ($tool in @("git", "gh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is required to publish."
    }
}

# gh resolves the repository from the current directory, so the whole run happens at the repo root.
$notesPath = $null
Push-Location -LiteralPath $repoRoot
try {
    $branchQuery = Invoke-Native git @("branch", "--show-current")
    $branch = if ($branchQuery.StdOut.Count -gt 0) { $branchQuery.StdOut[0] } else { "" }
    if ($branchQuery.ExitCode -ne 0 -or $branch -ne "main") {
        throw "Publishing is allowed only from main; current branch is '$branch'."
    }
    $treeDirty = Test-GitWorkingTreeDirty $repoRoot
    if ($null -eq $treeDirty) {
        throw "Could not read the working-tree status."
    }
    if ($treeDirty) {
        throw "Commit or remove working-tree changes before publishing. publish.ps1 never commits automatically."
    }
    $targetCommit = Get-GitHeadCommit $repoRoot
    if (-not $targetCommit) {
        throw "Could not resolve HEAD."
    }

    $repository = 'KwangBeomPark/01_ClipOCR-Pro'
    $ghRepository = "github.com/$repository"
    Assert-SuiteOrigin $repoRoot $repository
    $remoteMain = Invoke-Git $repoRoot @('ls-remote', 'origin', 'refs/heads/main') -Checked
    if ($remoteMain.StdOut.Count -ne 1 -or $remoteMain.StdOut[0] -notmatch "^$targetCommit\s+refs/heads/main$") { throw 'Push the reviewed source commit to origin/main before publication. This script never pushes.' }

    $null = Invoke-NativeChecked gh @("auth", "status", "--hostname", "github.com") "GitHub CLI authentication" -Quiet -FailureHint "Run 'gh auth login'."

    # A fully paginated successful query includes drafts and fails closed.
    $existingRelease = Get-SuiteRemoteRelease $repository $tag
    if ($existingRelease) {
        if ($existingRelease.draft) {
            throw "A draft release $tag already exists. Preserve it and review its verified assets before manually completing it, or choose a new version."
        }
        throw "GitHub release $tag already exists. Bump APP_VERSION instead of replacing it."
    }

    # A leftover tag would silently bind the release to whatever commit the tag points at.
    $tagQuery = Invoke-NativeChecked git @("ls-remote", "--tags", "origin", "refs/tags/$tag", "refs/tags/$tag^{}") "Remote tag query" -Quiet
    $remoteTagCommit = $null
    foreach ($line in $tagQuery.StdOut) {
        if ($line -match "^([0-9a-f]{40})\s+refs/tags/$([regex]::Escape($tag))(\^\{\})?$") {
            # The peeled ("^{}") entry is the commit behind an annotated tag.
            if ($null -eq $remoteTagCommit -or $Matches[2]) {
                $remoteTagCommit = $Matches[1]
            }
        }
    }
    if ($null -ne $remoteTagCommit -and $remoteTagCommit -ne $targetCommit) {
        throw "Tag $tag already exists on origin at $remoteTagCommit, not at HEAD ($targetCommit). Preserve it and choose a new version."
    }

    # Publication consumes the exact already-reviewed signed set. It never builds or signs.
    $outputRoot = $officialOutput
    $sourceDigest = Get-SuiteSourceDigest $repoRoot
    $null = Assert-SuiteRelease $outputRoot $version $targetCommit $sourceDigest -RequireClean
    $outputPaths = Get-BuildOutputPaths $outputRoot
    $manifestPath = $outputPaths.Manifest
    $checksumsPath = $outputPaths.Checksums
    $manifestData = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $waivers = @()
    $assets = @($manifestData.artifacts | ForEach-Object { Join-Path $outputRoot $_.name })
    $assets += $manifestPath
    $assets += $checksumsPath
    foreach ($asset in $assets) {
        if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
            throw "Missing release asset: $asset"
        }
    }

    # Release notes carry the signing facts from the manifest and any gate waiver, so the release
    # page records how the build was produced instead of only its version.
    $notesLines = @(
        "Release $tag",
        "",
        "Commit: $targetCommit",
        "Signed: $(if ($manifestData.signed) { 'yes' } else { 'no' })",
        "Timestamp: $($manifestData.timestampType)",
        "Signer: $(if ($manifestData.signerThumbprint) { "$($manifestData.signerThumbprint) ($($manifestData.signerSubject))" } else { '-' })",
        "Issuer: $(if ($manifestData.signerIssuer) { $manifestData.signerIssuer } else { '-' })",
        "Provenance: build-manifest.json and SHA256SUMS.txt (release assets)"
    )
    if ($waivers.Count -gt 0) {
        $notesLines += "Waivers: $($waivers -join ', ')"
        Write-Warning "Publishing with gate waivers: $($waivers -join ', ')"
    }
    # Certificate names may contain quotes, which Windows PowerShell cannot pass to a native tool
    # intact, so gh reads the notes from a file instead of an argument.
    $notesPath = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($notesPath, (($notesLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

    $action = "create immutable GitHub release $tag at verified commit $targetCommit"
    if (-not $PSCmdlet.ShouldProcess($repository, $action)) {
        return
    }
    if ((Get-GitHeadCommit $repoRoot) -ne $targetCommit -or (Test-GitWorkingTreeDirty $repoRoot) -ne $false -or (Get-SuiteSourceDigest $repoRoot) -ne $sourceDigest) { throw 'Source changed after build verification; publication refused.' }
    # Create the release as a draft so a failed asset upload never leaves a public, half-populated
    # release behind; publishing is the final step and is what creates the tag at the target commit.
    $createArgs = @("release", "create", $tag) + $assets + @(
        "--draft",
        "--repo", $ghRepository,
        "--target", $targetCommit,
        "--title", $tag,
        "--notes-file", $notesPath
    )
    $null = Invoke-NativeChecked gh $createArgs "GitHub release creation" -FailureHint "If a draft was left behind, preserve and review it. Retry only missing verified assets or select a new version; never delete or overwrite existing release assets."
    $verifiedRemote = Get-SuiteRemoteRelease $repository $tag
    if (-not $verifiedRemote -or $verifiedRemote.tag_name -ne $tag -or @(Get-SuiteMissingAssets $assets $verifiedRemote.assets).Count -ne 0) { throw 'Remote assets are incomplete. Preserve the draft and compare the verified local set before recovery.' }
    if ($Draft) {
        Write-Host "Draft release $tag is ready at $targetCommit; publish it from GitHub when appropriate."
        return
    }
    $null = Invoke-NativeChecked gh @("release", "edit", $tag, "--draft=false", "--repo", $ghRepository) "Publishing draft $tag" -FailureHint "Assets were uploaded; preserve and review the draft before manually completing publication."
    $published = Get-SuiteRemoteRelease $repository $tag
    if (-not $published -or $published.draft -ne $false -or @(Get-SuiteMissingAssets $assets $published.assets).Count -ne 0) { throw 'Public release state or assets could not be verified. Preserve the existing release.' }

    Write-Host "Published $tag at $targetCommit"
} finally {
    if ($notesPath -and (Test-Path -LiteralPath $notesPath)) {
        Remove-Item -LiteralPath $notesPath -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
