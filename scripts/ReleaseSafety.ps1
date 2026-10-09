# Side-effect-free helpers shared by build, signing and publication.
function Assert-SuiteWorkspacePath {
    param([string]$RepoRoot, [string]$Path)
    $base = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $root = $base + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output paths must stay inside this repository.' }
    $probe = $full
    while ($probe -and ($probe -eq $base -or $probe.StartsWith($root, [StringComparison]::OrdinalIgnoreCase))) {
        if (Test-Path -LiteralPath $probe) {
            if ((Get-Item -LiteralPath $probe).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Output paths cannot traverse a junction or symlink.' }
        }
        $probe = Split-Path -Parent $probe
    }
}
function Get-SuiteArtifactNames {
    param([string]$Version)
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid release version.' }
    @("App01_ClipOCR-Pro_Setup_v$Version.exe")
}

function Assert-SuiteOrigin {
    param([string]$RepoRoot, [string]$ExpectedRepository)
    $query = Invoke-Git $RepoRoot @('remote', 'get-url', 'origin') -Checked
    if ($query.StdOut.Count -ne 1) { throw 'Cannot resolve the publication origin.' }
    $escaped = [regex]::Escape($ExpectedRepository)
    if ($query.StdOut[0] -notmatch "^(?:https://github\.com/|git@github\.com:)$escaped(?:\.git)?/?$") { throw 'Publication origin differs from the expected GitHub repository.' }
}

function New-SuiteFullOcrPackage {
    param([string]$RepoRoot, [string]$ExecutablePath, [string]$OcrRoot, [string]$Version)
    $null = Get-SuiteArtifactNames $Version
    $directory = Join-Path $RepoRoot ('build\full-ocr-' + [guid]::NewGuid().ToString('N'))
    Assert-SuiteWorkspacePath $RepoRoot $directory
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { throw 'Verified application executable is missing before Full OCR packaging.' }
    $stage = Join-Path $directory 'stage'
    New-Item -ItemType Directory -Path $stage | Out-Null
    $copiedExe = Join-Path $stage 'ClipOCR-Pro.exe'
    Copy-Item -LiteralPath $ExecutablePath -Destination $copiedExe
    if ((Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $copiedExe -Algorithm SHA256).Hash) { throw 'Full OCR application copy differs from the verified executable.' }
    Copy-Item -LiteralPath $OcrRoot -Destination (Join-Path $stage 'ocr') -Recurse
    $zip = Join-Path $directory "App01_ClipOCR-Pro_v$Version-Full.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
    # Local optional package and diagnostic stage are intentionally retained outside official promotion.
    return $zip
}

function Get-SuiteSourceDigest {
    param([string]$RepoRoot)
    $files = Invoke-Git $RepoRoot @('ls-files', '--cached', '--others', '--exclude-standard', '--', 'src', 'scripts', 'tests', 'installer', 'assets') -Checked
    $lines = foreach ($name in @($files.StdOut | Sort-Object -Unique)) {
        $path = Join-Path $RepoRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Source file missing: $name" }
        "$( (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash )  $name"
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-SuiteSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or -not $signature.TimeStamperCertificate) {
        throw "Valid timestamped signature required: $Path"
    }
    [ordered]@{ status = 'Valid'; signerThumbprint = $signature.SignerCertificate.Thumbprint; timestampThumbprint = $signature.TimeStamperCertificate.Thumbprint }
}

function Assert-SuitePortable {
    param([string]$ZipPath, [string]$ExecutablePath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $expectedName = Split-Path -Leaf $ExecutablePath
        if ($archive.Entries.Count -ne 1 -or $archive.Entries[0].FullName -cne $expectedName) {
            throw 'Portable ZIP must contain exactly the verified executable.'
        }
        $stream = $archive.Entries[0].Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $stream.Dispose(); $sha.Dispose() }
        if ($hash -ne (Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256).Hash) { throw 'Portable executable bytes differ from the signed executable.' }
    } finally { $archive.Dispose() }
}

function Write-SuiteReleaseMetadata {
    param([string]$Directory, [string]$Version, $Provenance, [switch]$Signed)
    $artifacts = foreach ($name in Get-SuiteArtifactNames $Version) {
        $path = Join-Path $Directory $name
        $item = Get-Item -LiteralPath $path
        $entry = [ordered]@{ name = $name; bytes = $item.Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        if ($Signed -and $name.EndsWith('.exe')) { $entry.signature = Assert-SuiteSignature $path }
        [pscustomobject]$entry
    }
    $manifest = [ordered]@{ schemaVersion = 2; application = 'ClipOCR-Pro'; version = $Version; fileVersion = "$Version.0"; builtAtUtc = [DateTime]::UtcNow.ToString('o'); signed = [bool]$Signed; provenance = $Provenance; artifacts = @($artifacts) }
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $Directory 'build-manifest.json'), (($manifest | ConvertTo-Json -Depth 8) + "`n"), $encoding)
    [IO.File]::WriteAllText((Join-Path $Directory 'SHA256SUMS.txt'), ((@($artifacts | ForEach-Object { "$($_.sha256)  $($_.name)" }) -join "`n") + "`n"), $encoding)
}

function Assert-SuiteRelease {
    param([string]$Directory, [string]$Version, [string]$ExpectedCommit, [string]$ExpectedSourceDigest, [switch]$RequireClean)
    $manifest = Get-Content -LiteralPath (Join-Path $Directory 'build-manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 2 -or $manifest.application -ne 'ClipOCR-Pro' -or $manifest.version -ne $Version -or $manifest.fileVersion -ne "$Version.0" -or $manifest.signed -ne $true) { throw 'Unsupported or unsigned release manifest.' }
    if ($manifest.provenance.commit -notmatch '^[0-9a-f]{40}$' -or $manifest.provenance.sourceDigest -notmatch '^[0-9a-f]{64}$' -or $manifest.provenance.testsPassed -ne $true) { throw 'Missing successful build provenance.' }
    if ($ExpectedCommit -and $manifest.provenance.commit -ne $ExpectedCommit) { throw 'Release commit differs from HEAD.' }
    if ($ExpectedSourceDigest -and $manifest.provenance.sourceDigest -ne $ExpectedSourceDigest) { throw 'Release source digest differs from current source.' }
    if ($RequireClean -and $manifest.provenance.workingTreeDirty -ne $false) { throw 'Release was built from an uncommitted working tree.' }
    $names = @(Get-SuiteArtifactNames $Version)
    $allowedFiles = @($names) + @('build-manifest.json', 'SHA256SUMS.txt')
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $allowedFiles -cnotcontains $item.Name) { throw 'Unexpected file or directory in the official installer-only set.' }
    }
    if (@($manifest.artifacts).Count -ne $names.Count) { throw 'Unexpected manifest artifact count.' }
    $checksumLines = @(Get-Content -LiteralPath (Join-Path $Directory 'SHA256SUMS.txt'))
    if ($checksumLines.Count -ne $names.Count) { throw 'Unexpected checksum count.' }
    foreach ($name in $names) {
        $entry = @($manifest.artifacts | Where-Object { $_.name -ceq $name })
        if ($entry.Count -ne 1) { throw "Missing or duplicate artifact: $name" }
        $path = Join-Path $Directory $name
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($entry[0].sha256 -cne $hash -or $entry[0].bytes -ne (Get-Item -LiteralPath $path).Length -or @($checksumLines | Where-Object { $_ -ceq "$hash  $name" }).Count -ne 1) { throw "Artifact hash/size mismatch: $name" }
        if ($name.EndsWith('.exe')) {
            $actual = Assert-SuiteSignature $path
            if ($actual.signerThumbprint -ne $manifest.signerThumbprint) { throw "Unexpected signing certificate: $name" }
            if ($entry[0].signature.status -ne 'Valid' -or $entry[0].signature.signerThumbprint -ne $actual.signerThumbprint -or $entry[0].signature.timestampThumbprint -ne $actual.timestampThumbprint) { throw "Signature provenance mismatch: $name" }
        }
    }
    if ($manifest.compiledHealthCheck -ne 'passed' -or $manifest.signingMethod -ne 'store-signtool' -or $manifest.timestampType -ne 'rfc3161') { throw 'Official releases require compiled health checks and store-backed RFC3161 signing.' }
    $expectedIssuer = if ($env:CLIPOCR_RELEASE_SIGNER_ISSUER) { $env:CLIPOCR_RELEASE_SIGNER_ISSUER } else { 'CN=Certum Code Signing*' }
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Directory $names[0])
    if ($signature.SignerCertificate.Subject -eq $signature.SignerCertificate.Issuer -or $signature.SignerCertificate.Issuer -notlike $expectedIssuer -or $signature.SignerCertificate.Thumbprint -ne $manifest.signerThumbprint) { throw 'Unexpected or self-issued official signing certificate.' }
    $manifest
}

function Move-SuiteRelease {
    param([string]$RepoRoot, [string]$StagePath, [string]$ReleasePath, [scriptblock]$Validate)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($path in @($StagePath, $ReleasePath)) { Assert-SuiteWorkspacePath $RepoRoot $path }
    if ([IO.Path]::GetFullPath($ReleasePath) -ne (Join-Path $root 'release')) { throw 'Only the official repository release directory may be promoted.' }
    $stageFull = [IO.Path]::GetFullPath($StagePath).TrimEnd('\', '/')
    $releaseFull = [IO.Path]::GetFullPath($ReleasePath).TrimEnd('\', '/')
    if ($stageFull -eq $releaseFull -or $stageFull.StartsWith(($releaseFull + '\'), [StringComparison]::OrdinalIgnoreCase) -or $releaseFull.StartsWith(($stageFull + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Stage and official release must be separate directories.' }
    $null = & $Validate $StagePath
    if (Test-Path -LiteralPath $ReleasePath) {
        # A versioned artifact name is immutable even for local retry.
        foreach ($artifact in @(Get-ChildItem -LiteralPath $StagePath -File | Where-Object { $_.Extension -in @('.exe', '.zip') })) {
            $previous = Join-Path $ReleasePath $artifact.Name
            if ((Test-Path -LiteralPath $previous) -and (Get-FileHash -LiteralPath $previous -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash) { throw "Existing official artifact differs: $($artifact.Name). Choose the next release version; files will not be replaced." }
        }
    }
    $historyRoot = Join-Path $root 'build\release-history'
    Assert-SuiteWorkspacePath $RepoRoot $historyRoot
    New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
    $history = Join-Path $historyRoot ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $history) { throw 'Release archive collision; nothing was moved.' }
    $hadPrevious = Test-Path -LiteralPath $ReleasePath
    if ($hadPrevious) { Move-SuiteDirectory $ReleasePath $history }
    try {
        Move-SuiteDirectory $StagePath $ReleasePath
    } catch {
        if ($hadPrevious -and -not (Test-Path -LiteralPath $ReleasePath)) {
            try { Move-SuiteDirectory $history $ReleasePath }
            catch { throw "Promotion and restoration failed. Previous release remains preserved at $history. Diagnostic stage: $StagePath. $($_.Exception.Message)" }
        }
        elseif ($hadPrevious) { throw "Promotion failed and the official path is occupied. Previous release is preserved at $history. Review before restoration." }
        throw
    }
    if ($hadPrevious) { Write-Host "Previous official release preserved at $history" }
}

function Move-SuiteDirectory {
    param([string]$Source, [string]$Destination)
    # Directory.Move refuses an existing destination instead of nesting or overwriting.
    [IO.Directory]::Move($Source, $Destination)
}

function Get-SuiteMissingAssets {
    param([string[]]$LocalPaths, $RemoteAssets)
    $missing = @()
    foreach ($path in $LocalPaths) {
        $name = Split-Path -Leaf $path
        $matches = @($RemoteAssets | Where-Object { $_.name -ceq $name })
        if ($matches.Count -gt 1) { throw "Duplicate remote asset: $name" }
        if ($matches.Count -eq 0) { $missing += $path; continue }
        $expected = 'sha256:' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if (-not $matches[0].PSObject.Properties['digest'] -or $matches[0].digest -cne $expected -or $matches[0].size -ne (Get-Item -LiteralPath $path).Length) { throw "Remote asset digest/size mismatch or unavailable: $name. Existing assets will not be replaced." }
    }
    $missing
}
function Find-SuiteReleaseByTag {
    param([string]$Json, [string]$Tag)
    $pages = ConvertFrom-Json $Json
    $matches = @(foreach ($page in $pages) { foreach ($release in $page) { if ($release.tag_name -ceq $Tag) { $release } } })
    if ($matches.Count -gt 1) { throw 'Duplicate remote release tag.' }
    if ($matches.Count -eq 1) { $matches[0] }
}

function Get-SuiteRemoteRelease {
    param([string]$Repository, [string]$Tag)
    # REST tag lookup excludes drafts; a fully paginated list includes them for owners.
    $query = Invoke-NativeChecked gh @('api', "repos/$Repository/releases?per_page=100", '--hostname', 'github.com', '--paginate', '--slurp') 'Remote release query' -Quiet
    Find-SuiteReleaseByTag ($query.StdOut -join "`n") $Tag
}

