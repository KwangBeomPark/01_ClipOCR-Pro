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

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\ClipOCR-Pro.ahk"
$version = Get-AppVersion $sourcePath
$tag = "v$version"

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

    $null = Invoke-NativeChecked gh @("auth", "status") "GitHub CLI authentication" -Quiet -FailureHint "Run 'gh auth login'."

    # Fail closed: a failed query must never be mistaken for "no release yet".
    $releaseQuery = Invoke-NativeChecked gh @("release", "list", "--limit", "1000", "--json", "tagName,isDraft") "GitHub release query" -Quiet
    # Piping through ForEach-Object flattens the single array object Windows PowerShell 5.1 emits.
    $releases = @()
    $releaseJson = $releaseQuery.StdOut -join "`n"
    if ($releaseJson) {
        $releases = @(ConvertFrom-Json $releaseJson | ForEach-Object { $_ })
    }
    $existingRelease = @($releases | Where-Object { $_.tagName -eq $tag })
    if ($existingRelease.Count -gt 0) {
        if ($existingRelease[0].isDraft) {
            throw "A draft release $tag already exists (probably a failed earlier publish). Review it, then run 'gh release delete $tag --yes' and retry."
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
        throw "Tag $tag already exists on origin at $remoteTagCommit, not at HEAD ($targetCommit). Move or delete the tag before publishing."
    }

    & (Join-Path $PSScriptRoot "build.ps1") -OutputDirectory $OutputDirectory -IncludeEnterpriseAliases

    $outputRoot = Resolve-RepoPath $repoRoot $OutputDirectory
    $outputPaths = Get-BuildOutputPaths $outputRoot
    $manifestPath = $outputPaths.Manifest
    $checksumsPath = $outputPaths.Checksums
    $manifestData = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    # Each gate records its waiver where it is granted, so the release notes list exactly what was waived.
    $waivers = @()
    if ($manifestData.compiledHealthCheck -ne "passed") {
        throw "The compiled health check was '$($manifestData.compiledHealthCheck)' for this build; only builds whose compiled health check passed can be published."
    }
    if (-not $manifestData.signed) {
        if (-not $AllowUnsigned) {
            throw "Release is unsigned. Set CLIPOCR_SIGN_CERT_THUMBPRINT (certificate in the Windows store, e.g. Certum card or SimplySign) and CLIPOCR_TIMESTAMP_SERVER, or explicitly pass -AllowUnsigned."
        }
        $waivers += "-AllowUnsigned"
    } else {
        # A signed public release must come from the store-backed release certificate (never the
        # development PFX path), be issued by the release CA (a self-issued test certificate that happens
        # to be trusted locally is rejected), verify, and carry an RFC 3161 timestamp.
        if ($manifestData.signingMethod -notlike "store-*") {
            throw "The build was signed via '$($manifestData.signingMethod)', not the store-backed release certificate (CLIPOCR_SIGN_CERT_THUMBPRINT); PFX signing is the development fallback."
        }
        $expectedIssuerPattern = if ($env:CLIPOCR_RELEASE_SIGNER_ISSUER) { $env:CLIPOCR_RELEASE_SIGNER_ISSUER } else { "CN=Certum Code Signing*" }
        if ($manifestData.signerSubject -eq $manifestData.signerIssuer) {
            throw "The signer '$($manifestData.signerSubject)' is self-issued; public releases must be signed by the CA-issued release certificate."
        }
        if ($manifestData.signerIssuer -notlike $expectedIssuerPattern) {
            throw "The signer was issued by '$($manifestData.signerIssuer)', which does not match the expected release CA pattern '$expectedIssuerPattern' (set CLIPOCR_RELEASE_SIGNER_ISSUER if the CA legitimately changed)."
        }
        if ($manifestData.signatureStatus -ne "Valid") {
            throw "The signature status is '$($manifestData.signatureStatus)', not 'Valid': the certificate chain is not trusted on this machine. Install the CA's intermediate/root certificates and rebuild."
        }
        if ($manifestData.timestampType -eq "none") {
            throw "The signature is not timestamped; set CLIPOCR_TIMESTAMP_SERVER and rebuild."
        }
        if ($manifestData.timestampType -ne "rfc3161") {
            if (-not $AllowLegacyTimestamp) {
                throw "The signature carries a '$($manifestData.timestampType)' timestamp, not RFC 3161. Install the Windows SDK signing tools (signtool.exe) or set CLIPOCR_SIGNTOOL_PATH and rebuild, or explicitly pass -AllowLegacyTimestamp."
            }
            $waivers += "-AllowLegacyTimestamp"
        }
    }

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

    $action = "push main and create immutable GitHub release $tag at $targetCommit"
    if (-not $PSCmdlet.ShouldProcess("origin/main", $action)) {
        return
    }

    if (-not $NoPush) {
        $null = Invoke-NativeChecked git @("push", "origin", "main") "git push origin main"
    }

    # Create the release as a draft so a failed asset upload never leaves a public, half-populated
    # release behind; publishing is the final step and is what creates the tag at the target commit.
    $createArgs = @("release", "create", $tag) + $assets + @(
        "--draft",
        "--target", $targetCommit,
        "--title", $tag,
        "--notes-file", $notesPath
    )
    $null = Invoke-NativeChecked gh $createArgs "GitHub release creation" -FailureHint "If a draft $tag was left behind, run 'gh release delete $tag --yes' before retrying."
    if ($Draft) {
        Write-Host "Draft release $tag is ready at $targetCommit; publish it from GitHub when appropriate."
        return
    }
    $null = Invoke-NativeChecked gh @("release", "edit", $tag, "--draft=false") "Publishing draft $tag" -FailureHint "Assets were uploaded; retry with: gh release edit $tag --draft=false"

    Write-Host "Published $tag at $targetCommit"
} finally {
    if ($notesPath -and (Test-Path -LiteralPath $notesPath)) {
        Remove-Item -LiteralPath $notesPath -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
