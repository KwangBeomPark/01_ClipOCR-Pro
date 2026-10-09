# Compatibility entry point: rebuild a verified signed set, never resign official files in place.
[CmdletBinding()]
param(
    [string]$CertificateThumbprint = 'E9C72CF5090840A1805296525D56BE680622A7FD',
    [string]$TimestampServer = 'http://time.certum.pl',
    [string]$OutputDirectory = 'release',
    [string]$SignToolPath = $env:CLIPOCR_SIGNTOOL_PATH
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$arguments = @{ CertificateThumbprint = $CertificateThumbprint; TimestampServer = $TimestampServer; OutputDirectory = $OutputDirectory; SignToolPath = $SignToolPath }
& (Join-Path $PSScriptRoot 'release.ps1') @arguments
