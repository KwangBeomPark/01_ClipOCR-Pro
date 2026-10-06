# scripts/sign_release.ps1 - Automated Release Signing Script for ClipOCR-Pro
# Run this script in an ELEVATED (Administrator) PowerShell window.

[CmdletBinding()]
param(
    [string]$CertificateThumbprint = "E9C72CF5090840A1805296525D56BE680622A7FD",
    [string]$TimestampServer = "http://time.certum.pl",
    [string]$OutputDirectory = "release"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $repoRoot $OutputDirectory

if (-not (Test-Path -LiteralPath $targetDir)) {
    throw "Target directory not found: $targetDir. Please run scripts/build.ps1 first."
}

# 1. Administrator Privilege Check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "PowerShell is not running as Administrator. Smart card / SimplySign token private key access may fail."
}

# 2. Locate signtool.exe
$signtool = $null
$candidates = @(
    "C:\Dev\GitHub\06_Stepwise\release\build\signtool\signtool.exe",
    (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\x64\signtool.exe"),
    (Join-Path $env:ProgramFiles "Windows Kits\10\bin\x64\signtool.exe")
)
$onPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($null -ne $onPath) {
    $signtool = $onPath.Source
} else {
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            $signtool = $c
            break
        }
    }
}

if ($null -eq $signtool) {
    throw "signtool.exe not found. Please verify Windows SDK or Stepwise buildtools path."
}

Write-Host "Using signtool: $signtool" -ForegroundColor Cyan

# 3. Locate Target Installer Binaries to Sign
$setupFiles = @(Get-ChildItem -LiteralPath $targetDir -Filter "*Setup*.exe" | ForEach-Object { $_.FullName })
$appFiles = @(Get-ChildItem -LiteralPath $targetDir -Filter "*ClipOCR*.exe" | ForEach-Object { $_.FullName })
$filesToSign = @($setupFiles + $appFiles | Select-Object -Unique)

if ($filesToSign.Count -eq 0) {
    throw "No executable files found in $targetDir to sign."
}

# 4. Sign Each File
Write-Host "`n=== Signing Release Binaries ===" -ForegroundColor Cyan
foreach ($file in $filesToSign) {
    $fileName = Split-Path -Leaf $file
    Write-Host "Signing: $fileName..."
    $signArgs = @(
        "sign",
        "/debug",
        "/s", "my",
        "/sha1", $CertificateThumbprint,
        "/fd", "sha256",
        "/tr", $TimestampServer,
        "/td", "sha256",
        "/d", "ClipOCR-Pro"
    )
    $signArgs += $file

    & $signtool $signArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to sign $fileName (signtool exit code: $LASTEXITCODE). Ensure SimplySign Desktop or card reader is active and unlocked."
    }

    # Verify signature
    $sig = Get-AuthenticodeSignature -LiteralPath $file
    if ($sig.Status -ne "Valid") {
        throw "Signature verification failed for $($fileName): $($sig.Status)"
    }
    Write-Host "  [OK] Valid signature verified with timestamp: $($sig.TimeStamperCertificate.Subject)" -ForegroundColor Green
}

# 5. Re-generate SHA256SUMS.txt
Write-Host "`n=== Updating SHA256 Checksums ===" -ForegroundColor Cyan
$checksumsPath = Join-Path $targetDir "SHA256SUMS.txt"
$checksumLines = @()
foreach ($file in $setupFiles) {
    $item = Get-Item -LiteralPath $file
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumLines += "$hash  $($item.Name)"
    Write-Host "  $hash  $($item.Name)"
}
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($checksumsPath, (($checksumLines -join "`n") + "`n"), $utf8NoBom)

Write-Host "`n[SUCCESS] All release binaries signed and verified successfully!" -ForegroundColor Green
