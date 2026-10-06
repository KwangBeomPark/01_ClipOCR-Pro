# scripts/release.ps1 - One-Click Release Pipeline for ClipOCR-Pro
# Run this script in an ELEVATED (Administrator) PowerShell window for digital code signing.

[CmdletBinding()]
param(
    [string]$OutputDirectory = "release",
    [string]$CertificateThumbprint = "E9C72CF5090840A1805296525D56BE680622A7FD",
    [string]$TimestampServer = "http://time.certum.pl",
    [switch]$SkipSigning
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ClipOCR-Pro (App01) Release Pipeline   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Administrator check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "PowerShell is not running as Administrator. Smart Card / SimplySign token signing may fail."
}

# 2. Smart Card service check
$scard = Get-Service -Name SCardSvr -ErrorAction SilentlyContinue
if ($null -ne $scard -and $scard.Status -ne "Running") {
    Write-Host "Starting Smart Card service (SCardSvr)..." -ForegroundColor Yellow
    Start-Service -Name SCardSvr -ErrorAction SilentlyContinue
}

# 3. Clean prior release output folder
$targetDir = Join-Path $repoRoot $OutputDirectory
if (Test-Path -LiteralPath $targetDir) {
    Write-Host "Cleaning output directory: $targetDir"
    Get-ChildItem -Path $targetDir | Remove-Item -Recurse -Force
}

# 4. Invoke build.ps1
$buildScript = Join-Path $PSScriptRoot "build.ps1"
$buildArgs = @{
    OutputDirectory            = $OutputDirectory
    IncludeEnterpriseAliases   = $true
}

if (-not $SkipSigning) {
    $buildArgs["CertificateThumbprint"] = $CertificateThumbprint
    $buildArgs["TimestampServer"]       = $TimestampServer
}

Write-Host "Running build and packaging..." -ForegroundColor Cyan
& $buildScript @buildArgs

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
}

# 5. Output Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Release Build Successfully Completed! " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Get-ChildItem -LiteralPath $targetDir | Format-Table Name, Length, LastWriteTime -AutoSize
