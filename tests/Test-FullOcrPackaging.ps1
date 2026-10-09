[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\ReleaseSafety.ps1')
$fixture = Join-Path $repo ('build\full-package-test-' + [guid]::NewGuid().ToString('N'))
Assert-SuiteWorkspacePath $repo $fixture
New-Item -ItemType Directory -Path (Join-Path $fixture 'ocr\tessdata') | Out-Null
$exe = Join-Path $fixture 'verified-app.exe'
[IO.File]::WriteAllText($exe, 'verified-executable-fixture')
[IO.File]::WriteAllText((Join-Path $fixture 'ocr\tesseract.exe'), 'runtime-fixture')
[IO.File]::WriteAllText((Join-Path $fixture 'ocr\tessdata\eng.traineddata'), 'language-fixture')
$before = (Get-FileHash -LiteralPath $exe).Hash
$zip = New-SuiteFullOcrPackage $repo $exe (Join-Path $fixture 'ocr') '9.8.7'
$count = 0
function Assert-Test { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message }; $script:count++ }
Assert-Test ((Get-FileHash -LiteralPath $exe).Hash -eq $before) 'Original verified app was changed.'
Assert-Test ($zip.StartsWith((Join-Path $repo 'build\full-ocr-'), [StringComparison]::OrdinalIgnoreCase)) 'Optional package enters official release output.'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entry = @($archive.Entries | Where-Object { $_.FullName -eq 'ClipOCR-Pro.exe' })
    Assert-Test ($entry.Count -eq 1) 'Full package app is missing or duplicated.'
    $stream = $entry[0].Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $copied = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') } finally { $stream.Dispose(); $sha.Dispose() }
    Assert-Test ($copied -eq $before) 'Full package app differs from verified source.'
    Assert-Test (@($archive.Entries | Where-Object { $_.FullName -match 'ocr[/\\]tessdata[/\\]eng.traineddata' }).Count -eq 1) 'Full package lost OCR data.'
} finally { $archive.Dispose() }
$build = Get-Content -LiteralPath (Join-Path $repo 'scripts\build.ps1') -Raw
Assert-Test ($build.IndexOf('New-SuiteFullOcrPackage $repoRoot $exePath') -lt $build.IndexOf('foreach ($legacyFile')) 'Build removes app before optional packaging.'
Assert-Test ($build -notmatch '\$artifactPaths\.Add\(\$fullZipPath\)') 'Optional package is a public artifact.'
Write-Host "Full OCR packaging: $count assertions passed; owned fixtures retained at $fixture"
