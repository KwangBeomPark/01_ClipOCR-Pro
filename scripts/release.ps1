# Build and sign in a unique stage. Existing official files are never cleaned first.
[CmdletBinding()]
param(
    [string]$OutputDirectory = 'release',
    [string]$CertificateThumbprint = 'E9C72CF5090840A1805296525D56BE680622A7FD',
    [string]$TimestampServer = 'http://time.certum.pl',
    [string]$SignToolPath = $env:CLIPOCR_SIGNTOOL_PATH,
    [switch]$SkipSigning
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'ReleaseSafety.ps1')
$repoRoot = Split-Path -Parent $PSScriptRoot
$target = Resolve-RepoPath $repoRoot $OutputDirectory
if ($SkipSigning) {
    if ($target -eq (Join-Path $repoRoot 'release')) { throw 'Unsigned output belongs in dist/build; official release cannot be unsigned.' }
    & (Join-Path $PSScriptRoot 'build.ps1') -OutputDirectory $OutputDirectory -CertificateThumbprint '' -CertificatePath '' -IncludeEnterpriseAliases -SkipCompiledHealthCheck
    return
}
if ($target -ne (Join-Path $repoRoot 'release')) { throw 'Signed official output must be the repository release directory. Use build.ps1 for development signing.' }
if ((Test-GitWorkingTreeDirty $repoRoot) -ne $false) { throw 'Commit reviewed changes and choose the next version before building an official signed release.' }
$commit = Get-GitHeadCommit $repoRoot
if (-not $commit) { throw 'Cannot resolve source commit.' }
$version = Get-AppVersion (Join-Path $repoRoot 'src\ClipOCR-Pro.ahk')
$stage = Join-Path $repoRoot ('build\release-stage-' + [guid]::NewGuid().ToString('N'))
Assert-SuiteWorkspacePath $repoRoot $stage
Assert-SuiteWorkspacePath $repoRoot $target
$arguments = @{ OutputDirectory = $stage; CertificateThumbprint = $CertificateThumbprint; CertificatePath = ''; TimestampServer = $TimestampServer; IncludeEnterpriseAliases = $true }
if ($SignToolPath) { $arguments.SignToolPath = $SignToolPath }
& (Join-Path $PSScriptRoot 'build.ps1') @arguments
$digest = Get-SuiteSourceDigest $repoRoot
$null = Assert-SuiteRelease $stage $version $commit $digest -RequireClean
if ((Test-GitWorkingTreeDirty $repoRoot) -ne $false -or (Get-GitHeadCommit $repoRoot) -ne $commit) { throw 'Source changed while signing; official output was not modified.' }
$validate = { param($directory) Assert-SuiteRelease $directory $version $commit $digest -RequireClean }.GetNewClosure()
Move-SuiteRelease $repoRoot $stage $target $validate
Write-Host 'Verified signed local release prepared. Existing versions are preserved in build/release-history. Publication is a separate explicit action.'
