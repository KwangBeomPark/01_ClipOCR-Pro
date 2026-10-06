[CmdletBinding()]
param(
    [string]$OutputDirectory = "dist",
    [string]$AutoHotkeyPath = $env:AUTOHOTKEY_EXE_PATH,
    [string]$CompilerPath = $env:AHK2EXE_PATH,
    # Card/cloud certificates (Certum card, SimplySign) live in the Windows store and are selected by thumbprint.
    [string]$CertificateThumbprint = $env:CLIPOCR_SIGN_CERT_THUMBPRINT,
    # Development fallback only: a PFX with an exportable private key (self-signed test certificates).
    [string]$CertificatePath = $env:CLIPOCR_SIGN_CERT_PATH,
    [string]$TimestampServer = $env:CLIPOCR_TIMESTAMP_SERVER,
    [string]$SignToolPath = $env:CLIPOCR_SIGNTOOL_PATH,
    [switch]$SkipTimestamp,
    # Local development only (recorded in the manifest; publish.ps1 refuses such builds): machines with
    # Smart App Control on cannot start a fresh binary unless it is signed by a trusted CA.
    [switch]$SkipCompiledHealthCheck,
    # Full-package builds are an explicit choice; the app-side CLIPOCR_TESSERACT_DIR is never consulted.
    [string]$TesseractDirectory = "",
    [switch]$IncludeEnterpriseAliases
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Common.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\ClipOCR-Pro.ahk"
$iconPath = Join-Path $repoRoot "assets\ClipOCR-Pro.ico"

function Resolve-ExistingFile {
    param([string]$ConfiguredPath, [string]$DefaultPath, [string]$Description)

    $candidate = if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) { $DefaultPath } else { $ConfiguredPath }
    $candidate = Resolve-RepoPath $repoRoot $candidate
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "$Description was not found: $candidate"
    }
    return $candidate
}

# 1 = Smart App Control on (blocks unknown unsigned binaries), 2 = evaluation, 0/absent = off.
function Get-SmartAppControlState {
    $policy = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue
    if ($null -eq $policy) {
        return 0
    }
    return [int]$policy.VerifiedAndReputablePolicyState
}

# Smart App Control admits a fresh binary only when its signature chains to a trusted CA. One
# explanation serves the pre-compile prediction, the post-signing check and a blocked start.
function New-ApplicationControlMessage {
    param([string]$Context, [string]$Reason)

    return "${Context}: Windows Application Control (Smart App Control) refuses to run $Reason. Sign with a certificate that chains to a trusted CA (CLIPOCR_SIGN_CERT_THUMBPRINT), build on a machine without the policy, or pass -SkipCompiledHealthCheck for a local development build (publish.ps1 refuses such builds)."
}

# Predicts Application Control's trust decision for a certificate; revocation is not consulted
# because this is a prediction, not the signature verification done after signing.
function Test-CertificateChainTrusted {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        return $chain.Build($Certificate)
    } finally {
        $chain.Dispose()
    }
}

# The health check prints FAIL lines to stdout; piping the process captures them (and makes
# PowerShell wait for the GUI-subsystem executable) so a failure names the broken check. AutoHotkey
# routes its load-time warnings to stdout as well, and the baseline is zero warnings, so any warning
# line fails the build instead of scrolling past.
function Invoke-HealthCheck {
    param([string]$FilePath, [string[]]$Arguments, [string]$Description)

    $logHint = "(log: $env:TEMP\ClipOCR-Pro\health-check.log)"
    try {
        $result = Invoke-NativeChecked $FilePath $Arguments $Description -FailureHint $logHint
    } catch [Management.Automation.ApplicationFailedException] {
        # ERROR_ACCESS_DISABLED_BY_POLICY (1260) / ERROR_SYSTEM_INTEGRITY_POLICY_VIOLATION (4551): Smart App
        # Control or WDAC refused to start the binary.
        $win32 = $_.Exception.InnerException -as [ComponentModel.Win32Exception]
        if ($null -ne $win32 -and $win32.NativeErrorCode -in @(1260, 4551)) {
            $signature = Get-AuthenticodeSignature -LiteralPath $FilePath
            $reason = if ($null -ne $signature.SignerCertificate) {
                "'$FilePath': it is signed by $($signature.SignerCertificate.Thumbprint) but that signature is not trusted on this machine (status: $($signature.Status))"
            } else {
                "'$FilePath': it is not signed"
            }
            throw (New-ApplicationControlMessage "$Description could not start (Win32 error $($win32.NativeErrorCode))" $reason)
        }
        throw
    }
    $warnings = @($result.Lines | Where-Object { $_ -match '==> Warning:' })
    if ($warnings.Count -gt 0) {
        throw "$Description reported $($warnings.Count) AutoHotkey warning(s): $($warnings -join ' | ') $logHint"
    }
}

function Find-SignTool {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        return Resolve-ExistingFile $ConfiguredPath $ConfiguredPath "signtool.exe"
    }
    $onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -ne $onPath) {
        return $onPath.Source
    }
    $stepwiseSignTool = "C:\Dev\GitHub\06_Stepwise\release\build\signtool\signtool.exe"
    if (Test-Path -LiteralPath $stepwiseSignTool -PathType Leaf) {
        return $stepwiseSignTool
    }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
        return $null
    }
    $kitsRoot = Join-Path $programFilesX86 "Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitsRoot)) {
        return $null
    }
    # Versioned SDK folders (10.0.22621.0, ...) newest first, then the flat legacy layout.
    $versionDirs = @(Get-ChildItem -LiteralPath $kitsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' } |
        Sort-Object { [version]$_.Name } -Descending)
    foreach ($dir in $versionDirs) {
        $candidate = Join-Path $dir.FullName "x64\signtool.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    $legacy = Join-Path $kitsRoot "x64\signtool.exe"
    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        return $legacy
    }
    return $null
}

function Find-InnoSetupCompiler {
    $onPath = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($null -ne $onPath) {
        return $onPath.Source
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            return $cand
        }
    }
    return $null
}

function Invoke-FileSigning {
    param(
        [string]$TargetFilePath,
        $SigningContext,
        [string]$Description,
        [string]$Timestamp,
        [switch]$SkipTs,
        [string]$Hint
    )
    if ($null -eq $SigningContext) { return }
    if ($null -ne $SigningContext.SignTool) {
        $signArgs = @("sign") + $SigningContext.Selector + @("/fd", "sha256", "/d", $Description)
        if (-not $SkipTs) {
            $signArgs += @("/tr", $Timestamp, "/td", "sha256")
        }
        $signArgs += $TargetFilePath
        $null = Invoke-NativeChecked $SigningContext.SignTool $signArgs "signtool" -FailureHint $Hint
    } else {
        $signParams = @{ FilePath = $TargetFilePath; Certificate = $SigningContext.Certificate; HashAlgorithm = "SHA256" }
        if (-not $SkipTs) {
            $signParams.TimestampServer = $Timestamp
        }
        $cmdletResult = Set-AuthenticodeSignature @signParams
        if ($cmdletResult.Status -eq "NotSigned" -or $cmdletResult.SignatureType -eq "None") {
            throw "Set-AuthenticodeSignature could not sign with $($SigningContext.Certificate.Thumbprint): $($cmdletResult.Status) - $($cmdletResult.StatusMessage). $Hint"
        }
    }
}

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Could not find the application source: $sourcePath"
}

$ahkExe = Resolve-ExistingFile $AutoHotkeyPath "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "AutoHotkey v2 runtime"
$ahk2Exe = Resolve-ExistingFile $CompilerPath "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" "Ahk2Exe compiler"
$source = Get-Content -Raw -LiteralPath $sourcePath
$version = Get-AppVersion -SourceText $source
$expectedFileVersion = "$version.0"
$directiveFileVersion = Get-Ahk2ExeFileVersion -SourceText $source
if ($directiveFileVersion -ne $expectedFileVersion) {
    throw "APP_VERSION ($version) and the Ahk2Exe file version ($directiveFileVersion) are not synchronized; expected $expectedFileVersion."
}

# Capture source provenance before this build creates or replaces any output files.
$sourceCommit = Get-GitHeadCommit $repoRoot
$sourceTreeDirty = Test-GitWorkingTreeDirty $repoRoot
if ($null -eq $sourceCommit -or $null -eq $sourceTreeDirty) {
    $sourceCommit = ""
    $sourceTreeDirty = $false
}

$outputRoot = Resolve-RepoPath $repoRoot $OutputDirectory
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$baseName = "ClipOCR-Pro.v$version"
$exePath = Join-Path $outputRoot "$baseName.exe"
$zipPath = Join-Path $outputRoot "$baseName.zip"
$outputPaths = Get-BuildOutputPaths $outputRoot
$manifestPath = $outputPaths.Manifest
$checksumsPath = $outputPaths.Checksums
$fullZipPath = Join-Path $outputRoot "App01_ClipOCR-Pro_v$version-Full.zip"
$portableOcrRoot = $null
$portableOcrVersion = ""
if ([string]::IsNullOrWhiteSpace($TesseractDirectory) -and -not [string]::IsNullOrWhiteSpace($env:CLIPOCR_TESSERACT_DIR)) {
    Write-Host "  Note: CLIPOCR_TESSERACT_DIR is an app-side setting and is ignored by the build; pass -TesseractDirectory to produce the Full package."
}
if (-not [string]::IsNullOrWhiteSpace($TesseractDirectory)) {
    $portableOcrRoot = Resolve-RepoPath $repoRoot $TesseractDirectory
    foreach ($requiredPath in @(
        (Join-Path $portableOcrRoot "tesseract.exe"),
        (Join-Path $portableOcrRoot "tessdata\kor.traineddata"),
        (Join-Path $portableOcrRoot "tessdata\eng.traineddata")
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Full OCR package requires an approved portable Tesseract runtime with kor and eng data: $requiredPath"
        }
    }
    # Tesseract writes its banner and language list to stderr, so both streams are inspected.
    $tesseractExe = Join-Path $portableOcrRoot "tesseract.exe"
    $versionResult = Invoke-Native $tesseractExe @("--version") -MergeStdErr
    if ($versionResult.ExitCode -ne 0 -or $versionResult.Lines.Count -eq 0) {
        throw "The approved Tesseract runtime could not be executed. Verify its DLLs and company deployment package."
    }
    $portableOcrVersion = $versionResult.Lines[0]
    $languageResult = Invoke-Native $tesseractExe @("--tessdata-dir", (Join-Path $portableOcrRoot "tessdata"), "--list-langs") -MergeStdErr
    if ($languageResult.ExitCode -ne 0 -or -not ($languageResult.Lines -contains "kor") -or -not ($languageResult.Lines -contains "eng")) {
        throw "The approved Tesseract runtime did not report both kor and eng language data."
    }
}
$targetArtifacts = @($exePath, $zipPath, $manifestPath, $checksumsPath)
if ($null -ne $portableOcrRoot) {
    $targetArtifacts += $fullZipPath
}
if ($IncludeEnterpriseAliases) {
    $targetArtifacts += Join-Path $outputRoot "App01_ClipOCR-Pro_v$version.exe"
    $targetArtifacts += Join-Path $outputRoot "App01_ClipOCR-Pro_v$version.zip"
}
foreach ($target in $targetArtifacts) {
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        Remove-Item -LiteralPath $target -Force
    }
}

# Card and cloud tokens (Certum card, SimplySign) expose the key through a provider that fails
# when the token is absent; this hint accompanies every signing failure.
$tokenHint = "For a card or cloud certificate make sure the token is connected (SimplySign: open SimplySign Desktop and connect it with the mobile app so the virtual smart card is present), then rerun and enter the PIN when prompted."

# Resolves the certificate, the signing tool and the timestamp policy before any compile work, so a
# configuration mistake is reported immediately; $null when signing is not configured. The key itself
# is exercised only by the real signer (a probe would prompt for the token PIN a second time).
function Resolve-SigningContext {
    $useStore = -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)
    if (-not $useStore -and [string]::IsNullOrWhiteSpace($CertificatePath)) {
        return $null
    }
    if (-not $SkipTimestamp -and [string]::IsNullOrWhiteSpace($TimestampServer)) {
        throw "Signing requires an RFC 3161 timestamp server so the signature outlives the certificate. Set CLIPOCR_TIMESTAMP_SERVER (Certum: http://time.certum.pl) or pass -SkipTimestamp for local test builds."
    }
    if ($useStore) {
        # Card / cloud certificates (Certum card, SimplySign Desktop) appear in the Windows store
        # with a provider-backed private key that never leaves the token.
        $thumbprint = ConvertTo-CertificateThumbprint $CertificateThumbprint
        $certificate = @(Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $thumbprint }) | Select-Object -First 1
        if ($null -eq $certificate) {
            throw "No certificate with thumbprint $thumbprint in CurrentUser\My or LocalMachine\My. Insert the card or start SimplySign Desktop, then list candidates with: Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert"
        }
        if (-not $certificate.HasPrivateKey) {
            throw "Certificate $thumbprint has no private-key link in the store; import it through the token vendor's software."
        }
        $selector = @("/sha1", $thumbprint)
        if ([string]$certificate.PSParentPath -like "*LocalMachine*") {
            $selector += "/sm"
        }
        $origin = "store"
    } else {
        # Development fallback only: a PFX with an exportable private key (self-signed test certificates).
        # The password reaches signtool on its command line, which is acceptable for local test builds only.
        $certificateFile = Resolve-ExistingFile $CertificatePath $CertificatePath "Signing certificate"
        $passwordText = [string]$env:CLIPOCR_SIGN_CERT_PASSWORD
        $flags = [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile, $passwordText, $flags)
        if (-not $certificate.HasPrivateKey) {
            throw "The configured certificate does not contain a private key. A .cer file cannot sign releases."
        }
        $selector = @("/f", $certificateFile)
        if ($passwordText) {
            $selector += @("/p", $passwordText)
        }
        # Windows PowerShell 5.1 cannot pass an embedded quote or a trailing backslash to a native tool intact.
        if ($passwordText -match '"' -or $passwordText.EndsWith('\')) {
            Write-Warning "The PFX password contains characters that cannot be passed to signtool from Windows PowerShell; signing with Set-AuthenticodeSignature instead."
            $selector = $null
        }
        $origin = "pfx"
    }

    # signtool (Windows SDK) applies an RFC 3161 timestamp; the PowerShell cmdlet can only apply the
    # legacy Authenticode timestamp, so that fallback is announced here and gated again by publish.ps1.
    $signtool = $null
    if ($null -ne $selector) {
        $signtool = Find-SignTool $SignToolPath
        if ($null -eq $signtool) {
            Write-Warning "signtool.exe was not found; signing with Set-AuthenticodeSignature (legacy Authenticode timestamp). Install the Windows SDK signing tools or set CLIPOCR_SIGNTOOL_PATH for release builds."
        }
    }
    return [pscustomobject]@{
        Certificate   = $certificate
        Selector      = $selector
        SignTool      = $signtool
        Method        = "$origin-$(if ($null -ne $signtool) { 'signtool' } else { 'powershell' })"
        TimestampType = if ($SkipTimestamp) { "none" } elseif ($null -ne $signtool) { "rfc3161" } else { "authenticode" }
    }
}

$signing = Resolve-SigningContext
if ($null -ne $signing) {
    Write-Host "[0/5] Signing with $($signing.Certificate.Thumbprint) via $($signing.Method) (timestamp: $($signing.TimestampType))."
}
# The compiled health check starts the fresh binary, which Smart App Control allows only with a
# signature that chains to a trusted CA; predict that before compiling and confirm it after signing.
$applicationControlEnforced = -not $SkipCompiledHealthCheck -and (Get-SmartAppControlState) -eq 1
if ($applicationControlEnforced) {
    if ($null -eq $signing) {
        throw (New-ApplicationControlMessage "Smart App Control is on" "an unsigned build")
    }
    if (-not (Test-CertificateChainTrusted $signing.Certificate)) {
        throw (New-ApplicationControlMessage "Smart App Control is on" "a build signed with $($signing.Certificate.Thumbprint), which does not chain to a trusted CA on this machine")
    }
}

Write-Host "[1/5] Running source health check..."
Invoke-HealthCheck $ahkExe @("/ErrorStdOut", $sourcePath, "--health-check") "Source health check"

Write-Host "[2/5] Compiling $baseName.exe..."
$null = Invoke-NativeChecked $ahk2Exe @("/in", $sourcePath, "/out", $exePath, "/icon", $iconPath, "/base", $ahkExe, "/silent", "verbose") "Ahk2Exe compilation"
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Compiler did not create $exePath"
}

$compiledVersion = (Get-Item -LiteralPath $exePath).VersionInfo.FileVersion
if ($compiledVersion -ne $expectedFileVersion) {
    throw "Compiled EXE version ($compiledVersion) does not match $expectedFileVersion."
}

# Signing facts recorded in the manifest (and gated by publish.ps1); every value below is taken
# from the signature as verified on the file, not from the configuration.
$signingRecord = [ordered]@{
    signed           = $false
    signatureStatus  = "NotSigned"
    signingMethod    = "none"
    signerThumbprint = ""
    signerSubject    = ""
    signerIssuer     = ""
    timestampType    = "none"
}
if ($null -ne $signing) {
    Write-Host "[3/5] Signing executable..."
    Invoke-FileSigning $exePath $signing "ClipOCR-Pro" $TimestampServer -SkipTs:$SkipTimestamp -Hint $tokenHint
    $signature = Get-AuthenticodeSignature -LiteralPath $exePath
    if ($null -eq $signature.SignerCertificate -or $signature.SignatureType -eq "None") {
        throw "Authenticode signing did not produce a signature. Status: $($signature.Status)"
    }
    if (-not $SkipTimestamp -and $null -eq $signature.TimeStamperCertificate) {
        throw "The signature carries no timestamp; check CLIPOCR_TIMESTAMP_SERVER ($TimestampServer)."
    }
    $signingRecord.signed = $true
    $signingRecord.signatureStatus = [string]$signature.Status
    $signingRecord.signingMethod = $signing.Method
    $signingRecord.signerThumbprint = [string]$signature.SignerCertificate.Thumbprint
    $signingRecord.signerSubject = [string]$signature.SignerCertificate.Subject
    $signingRecord.signerIssuer = [string]$signature.SignerCertificate.Issuer
    $signingRecord.timestampType = $signing.TimestampType
    Write-Host "  Signed with $($signingRecord.signerThumbprint) ($($signingRecord.signerSubject)) via $($signingRecord.signingMethod) (status: $($signingRecord.signatureStatus), timestamp: $($signingRecord.timestampType))."
    if ($applicationControlEnforced -and $signingRecord.signatureStatus -ne "Valid") {
        throw (New-ApplicationControlMessage "The signature did not verify" "'$exePath' (signature status: $($signingRecord.signatureStatus))")
    }
} else {
    Write-Host "[3/5] Signing skipped (neither CLIPOCR_SIGN_CERT_THUMBPRINT nor CLIPOCR_SIGN_CERT_PATH is configured)."
}

$compiledHealthCheck = "passed"
if ($SkipCompiledHealthCheck) {
    Write-Warning "[4/5] Compiled health check skipped (-SkipCompiledHealthCheck): this is a development build and cannot be published."
    $compiledHealthCheck = "skipped"
} else {
    Write-Host "[4/5] Running compiled health check and creating archives..."
    Invoke-HealthCheck $exePath @("--health-check") "Compiled health check"
}
Compress-Archive -LiteralPath $exePath -DestinationPath $zipPath -CompressionLevel Optimal

$artifactPaths = [System.Collections.Generic.List[string]]::new()
$artifactPaths.Add($exePath)
$artifactPaths.Add($zipPath)

# Build Per-User Windows Installer using Inno Setup
$iscc = Find-InnoSetupCompiler
if ($null -ne $iscc) {
    Write-Host "  Building installer with Inno Setup ($iscc)..."
    $setupIssPath = Join-Path $repoRoot "installer\setup.iss"
    $isccArgs = @("/DMyAppVersion=$version", "/DMyAppExeSource=$exePath", "/O$outputRoot", $setupIssPath)
    $null = Invoke-NativeChecked $iscc $isccArgs "Inno Setup compilation"
    $setupExePath = Join-Path $outputRoot "ClipOCR-Setup.v$version.exe"
    if (Test-Path -LiteralPath $setupExePath -PathType Leaf) {
        if ($null -ne $signing) {
            Invoke-FileSigning $setupExePath $signing "ClipOCR-Pro Setup" $TimestampServer -SkipTs:$SkipTimestamp -Hint $tokenHint
        }
        $artifactPaths.Add($setupExePath)
        if ($IncludeEnterpriseAliases) {
            $enterpriseSetup = Join-Path $outputRoot "App01_ClipOCR-Setup_v$version.exe"
            Copy-Item -LiteralPath $setupExePath -Destination $enterpriseSetup -Force
            $artifactPaths.Add($enterpriseSetup)
        }
    }
} else {
    Write-Warning "Inno Setup compiler (ISCC.exe) was not found; installer build skipped."
}

if ($IncludeEnterpriseAliases) {
    $enterpriseExe = Join-Path $outputRoot "App01_ClipOCR-Pro_v$version.exe"
    $enterpriseZip = Join-Path $outputRoot "App01_ClipOCR-Pro_v$version.zip"
    Copy-Item -LiteralPath $exePath -Destination $enterpriseExe -Force
    Copy-Item -LiteralPath $zipPath -Destination $enterpriseZip -Force
    $artifactPaths.Add($enterpriseExe)
    $artifactPaths.Add($enterpriseZip)
}
if ($null -ne $portableOcrRoot) {
    $fullStage = Join-Path $outputRoot ".full-stage-$([Diagnostics.Process]::GetCurrentProcess().Id)"
    if (Test-Path -LiteralPath $fullStage) {
        Remove-Item -LiteralPath $fullStage -Recurse -Force
    }
    try {
        New-Item -ItemType Directory -Path $fullStage | Out-Null
        Copy-Item -LiteralPath $exePath -Destination (Join-Path $fullStage "ClipOCR-Pro.exe")
        Copy-Item -LiteralPath $portableOcrRoot -Destination (Join-Path $fullStage "ocr") -Recurse
        Compress-Archive -Path (Join-Path $fullStage "*") -DestinationPath $fullZipPath -CompressionLevel Optimal
        $artifactPaths.Add($fullZipPath)
    } finally {
        if (Test-Path -LiteralPath $fullStage) {
            Remove-Item -LiteralPath $fullStage -Recurse -Force
        }
    }
}

Write-Host "[5/5] Writing checksums and build manifest..."
$artifactInfo = foreach ($path in $artifactPaths) {
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        name   = $item.Name
        bytes  = $item.Length
        sha256 = $hash
    }
}
# .NET writers are used because Windows PowerShell 5.1 has no BOM-less UTF-8 -Encoding value.
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$checksumLines = @($artifactInfo | ForEach-Object { "$($_.sha256)  $($_.name)" })
[IO.File]::WriteAllText($checksumsPath, (($checksumLines -join "`n") + "`n"), $utf8NoBom)

$manifest = [ordered]@{
    application      = "ClipOCR-Pro"
    version          = $version
    fileVersion      = $expectedFileVersion
    commit           = $sourceCommit
    workingTreeDirty = $sourceTreeDirty
    builtAtUtc       = [DateTime]::UtcNow.ToString("o")
}
foreach ($key in $signingRecord.Keys) {
    $manifest[$key] = $signingRecord[$key]
}
$manifest.compiledHealthCheck = $compiledHealthCheck
$manifest.fullOcrPackage = ($null -ne $portableOcrRoot)
$manifest.portableOcrVersion = $portableOcrVersion
$manifest.artifacts = @($artifactInfo)
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 5) + "`n"), $utf8NoBom)

Write-Host "Build complete: $outputRoot"
