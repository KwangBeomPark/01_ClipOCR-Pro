[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Common.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\ReleaseSafety.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('clipocr-release-test-' + [guid]::NewGuid().ToString('N'))
$count = 0
function Assert-Test { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message }; $script:count++ }
function Expect-Failure { param([scriptblock]$Action, [string]$Message); $failed = $false; try { $null = & $Action } catch { $failed = $true }; Assert-Test $failed $Message }
$version = '9.8.7'
$commit = 'a' * 40
$digest = 'b' * 64
$provenance = [pscustomobject]@{ commit = $commit; sourceDigest = $digest; testsPassed = $true; workingTreeDirty = $false }
$script:signatureStatus = 'Valid'
$script:hasTimestamp = $true
$script:signer = 'fixture-signer'
function Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    [pscustomobject]@{ Status = $script:signatureStatus; SignerCertificate = [pscustomobject]@{ Thumbprint = $script:signer; Subject = 'CN=Fixture Publisher'; Issuer = 'CN=Certum Code Signing Fixture' }; TimeStamperCertificate = $(if ($script:hasTimestamp) { [pscustomobject]@{ Thumbprint = 'fixture-timestamp' } } else { $null }) }
}
$metadataWriter = ${function:Write-SuiteReleaseMetadata}
function Write-SuiteReleaseMetadata {
    param([string]$Directory, [string]$Version, $Provenance, [switch]$Signed)
    & $metadataWriter $Directory $Version $Provenance -Signed:$Signed
    $path = Join-Path $Directory 'build-manifest.json'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $manifest | Add-Member -NotePropertyName compiledHealthCheck -NotePropertyValue 'passed'
    $manifest | Add-Member -NotePropertyName signingMethod -NotePropertyValue 'store-signtool'
    $manifest | Add-Member -NotePropertyName timestampType -NotePropertyValue 'rfc3161'
    $manifest | Add-Member -NotePropertyName signerThumbprint -NotePropertyValue $script:signer
    [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}
function Reset-Set {
    param([string]$Directory)
    $names = @(Get-SuiteArtifactNames $version)
    [IO.File]::WriteAllText((Join-Path $Directory $names[0]), 'installer-fixture')
    Write-SuiteReleaseMetadata $Directory $version $provenance -Signed
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $stage = Join-Path $fixture 'stage'
    New-Item -ItemType Directory -Path $stage | Out-Null
    Reset-Set $stage
    $null = Assert-SuiteRelease $stage $version $commit $digest -RequireClean
    Assert-Test $true 'Valid fixture set must pass.'
    $names = @(Get-SuiteArtifactNames $version)
    $setup = Join-Path $stage $names[0]
    Assert-Test ($names.Count -eq 1) 'Official set must contain exactly one installer.'
    $exe = Join-Path $fixture 'missing-upload-fixture.exe'
    [IO.File]::WriteAllText($exe, 'non-public-fixture')
    Expect-Failure { Assert-SuiteRelease $stage $version ('c' * 40) $digest } 'Wrong commit accepted.'
    Expect-Failure { Assert-SuiteRelease $stage $version $commit ('c' * 64) } 'Wrong source digest accepted.'
    $provenance.testsPassed = $false; Write-SuiteReleaseMetadata $stage $version $provenance -Signed
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Skipped test gate accepted.'
    $provenance.testsPassed = $true; $provenance.workingTreeDirty = $true; Write-SuiteReleaseMetadata $stage $version $provenance -Signed
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest -RequireClean } 'Dirty publication accepted.'
    $provenance.workingTreeDirty = $false; Reset-Set $stage
    $script:signatureStatus = 'NotSigned'
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Unsigned executable accepted.'
    $script:signatureStatus = 'Valid'; $script:hasTimestamp = $false
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Missing timestamp accepted.'
    $script:hasTimestamp = $true; $script:signer = 'other-signer'
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Changed signer accepted.'
    $script:signer = 'fixture-signer'
    $draft = Find-SuiteReleaseByTag '[[{"tag_name":"v0","draft":false}],[{"tag_name":"v9.8.7","draft":true}]]' 'v9.8.7'
    Assert-Test ($draft.draft -eq $true) 'Draft on a later page was not found.'
    Assert-Test ($null -eq (Find-SuiteReleaseByTag '[[{"tag_name":"v0"}]]' 'v9.8.7')) 'Absent release was invented.'
    Expect-Failure { Find-SuiteReleaseByTag '[[{"tag_name":"v9.8.7"}],[{"tag_name":"v9.8.7"}]]' 'v9.8.7' } 'Duplicate remote release accepted.'
    Add-Content -LiteralPath $setup 'tampered'
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Tampered installer accepted.'
    Reset-Set $stage
    $manifestPath = Join-Path $stage 'build-manifest.json'
    $extraManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $extraManifest.artifacts = @($extraManifest.artifacts) + @($extraManifest.artifacts[0])
    [IO.File]::WriteAllText($manifestPath, ($extraManifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Duplicate installer metadata accepted.'
    Reset-Set $stage
    [IO.File]::WriteAllText((Join-Path $stage 'obsolete-alias.exe'), 'extra-public-file')
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Unexpected public file accepted.'
    Remove-Item -LiteralPath (Join-Path $stage 'obsolete-alias.exe')
    Reset-Set $stage
    Add-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') 'extra'
    Expect-Failure { Assert-SuiteRelease $stage $version $commit $digest } 'Extra checksum entry accepted.'
    Reset-Set $stage
    $remote = @([pscustomobject]@{ name = $names[0]; size = (Get-Item -LiteralPath $setup).Length; digest = 'sha256:' + (Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant() })
    $missing = @(Get-SuiteMissingAssets @($setup, $exe) $remote)
    Assert-Test ($missing.Count -eq 1 -and $missing[0] -eq $exe) 'Resume must return only missing assets.'
    $remote[0].digest = 'sha256:' + ('0' * 64)
    Expect-Failure { Get-SuiteMissingAssets @($setup) $remote } 'Remote digest conflict accepted.'
    Expect-Failure { Get-SuiteMissingAssets @($setup) @([pscustomobject]@{ name = $names[0]; size = 17 }) } 'Missing remote digest accepted.'
    $release = Join-Path $fixture 'release'
    New-Item -ItemType Directory -Path $release | Out-Null
    [IO.File]::WriteAllText((Join-Path $release 'previous.txt'), 'previous-release')
    [IO.File]::WriteAllText((Join-Path $release $names[0]), 'different-official-installer')
    Expect-Failure { Move-SuiteRelease $fixture $stage $release { param($path) Assert-SuiteRelease $path $version $commit $digest } } 'Existing versioned artifact collision accepted.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $release $names[0]) -Raw) -eq 'different-official-installer') 'Collision changed original official bytes.'
    Remove-Item -LiteralPath (Join-Path $release $names[0])
    Expect-Failure { Move-SuiteRelease $fixture $stage $release { throw 'injected verification failure' } } 'Verification failure did not stop promotion.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $release 'previous.txt') -Raw) -eq 'previous-release') 'Verification failure changed official files.'
    $collisionSource = Join-Path $fixture 'collision-source'
    $collisionDestination = Join-Path $fixture 'collision-destination'
    New-Item -ItemType Directory -Path $collisionSource, $collisionDestination | Out-Null
    Expect-Failure { Move-SuiteDirectory $collisionSource $collisionDestination } 'Existing archive destination was accepted.'
    Assert-Test (Test-Path -LiteralPath $collisionSource) 'Archive collision changed source.'
    $directoryMover = ${function:Move-SuiteDirectory}
    $script:failStage = $stage
    function Move-SuiteDirectory {
        param([string]$LiteralPath, [string]$Destination)
        if ($LiteralPath -eq $script:failStage) { throw 'Injected final rename failure.' }
        [IO.Directory]::Move($LiteralPath, $Destination)
    }
    Expect-Failure { Move-SuiteRelease $fixture $stage $release { param($path) Assert-SuiteRelease $path $version $commit $digest } } 'Injected rename failure did not stop.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $release 'previous.txt') -Raw) -eq 'previous-release') 'Rename failure did not restore old official files.'
    Assert-Test (Test-Path -LiteralPath (Join-Path $stage $names[0])) 'Rename failure lost diagnostic stage.'
    Set-Item Function:\Move-SuiteDirectory -Value $directoryMover
    Move-SuiteRelease $fixture $stage $release { param($path) Assert-SuiteRelease $path $version $commit $digest }
    Assert-Test (Test-Path -LiteralPath (Join-Path $release $names[0])) 'Successful promotion missing new files.'
    $archived = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'build\release-history') -Filter 'previous.txt' -File -Recurse)
    Assert-Test ($archived.Count -eq 1 -and (Get-Content -LiteralPath $archived[0].FullName -Raw) -eq 'previous-release') 'Previous release was not preserved.'
    Expect-Failure { Move-SuiteRelease $fixture $release $release { } } 'Stage equal to release accepted.'
    Expect-Failure { Move-SuiteRelease $fixture $fixture $release { } } 'Ancestor stage accepted.'
    Expect-Failure { Move-SuiteRelease $fixture (Join-Path ([IO.Path]::GetTempPath()) 'outside') $release { } } 'Outside repository stage accepted.'
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $installerText = Get-Content -LiteralPath (Join-Path $repoRoot 'installer\setup.iss') -Raw
    $outputMatch = [regex]::Match($installerText, '(?m)^OutputBaseFilename=(.+)$')
    $outputName = $outputMatch.Groups[1].Value.Trim().Replace('{#MyAppVersion}', $version) + '.exe'
    Assert-Test ($outputName -ceq $names[0]) 'Installer output and signed artifact name differ.'
    foreach ($scriptFile in @('build.ps1', 'sign_release.ps1', 'publish.ps1', 'release.ps1', 'ReleaseSafety.ps1')) {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot "scripts\$scriptFile"), [ref]$tokens, [ref]$errors)
        Assert-Test ($errors.Count -eq 0) "PowerShell syntax failed: $scriptFile"
    }
    $signText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\sign_release.ps1') -Raw
    Assert-Test ($signText -notmatch '--clobber|release delete|Start-Service') 'Unsafe signing/publication operation restored.'
    $buildText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\build.ps1') -Raw
    Assert-Test ($buildText -notmatch 'C:\\Dev\\GitHub\\06_Stepwise') 'Cross-project tool path restored.'
    $publishText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\publish.ps1') -Raw
    Assert-Test ($publishText -notmatch 'Move-SuiteRelease|& \(Join-Path \$PSScriptRoot ["'']build\.ps1') 'Publication rebuilds or promotes local assets.'
    Assert-Test ($publishText -match "--repo" -and $publishText -match 'Assert-SuiteOrigin') 'Publication does not pin and validate its repository.'
    Assert-Test ($publishText -match '--draft' -and $publishText.IndexOf('Get-SuiteMissingAssets') -lt $publishText.LastIndexOf('--draft=false')) 'Publication exposes an unverified upload set.'
    $invokeGitOriginal = ${function:Invoke-Git}
    try {
        function Invoke-Git { param([string]$RepoRoot, [string[]]$Arguments, [switch]$Checked); [pscustomobject]@{ StdOut = @('https://github.com/KwangBeomPark/EXPECTED.git') } }
        Assert-SuiteOrigin $repoRoot 'KwangBeomPark/EXPECTED'
        Assert-Test $true 'Matching explicit origin rejected.'
        Expect-Failure { Assert-SuiteOrigin $repoRoot 'KwangBeomPark/DIFFERENT' } 'Wrong publication origin accepted.'
    } finally { Set-Item Function:\Invoke-Git -Value $invokeGitOriginal }
    $official = Join-Path $repoRoot 'release'
    $before = @(Get-ChildItem -LiteralPath $official -File | Sort-Object Name | ForEach-Object { "$($_.Name):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join "`n"
    foreach ($arguments in @(
        @('-File', (Join-Path $repoRoot 'scripts\build.ps1'), '-OutputDirectory', 'release'),
        @('-File', (Join-Path $repoRoot 'scripts\build.ps1'), '-OutputDirectory', 'release\nested'),
        @('-File', (Join-Path $repoRoot 'scripts\release.ps1'), '-SkipSigning'),
        @('-File', (Join-Path $repoRoot 'scripts\publish.ps1'), '-AllowUnsigned'),
        @('-File', (Join-Path $repoRoot 'scripts\publish.ps1'), '-AllowLegacyTimestamp')
    )) {
        $result = Invoke-Native powershell.exe (@('-NoProfile', '-ExecutionPolicy', 'Bypass') + $arguments)
        Assert-Test ($result.ExitCode -ne 0) 'An unsafe entry point was accepted.'
    }
    $after = @(Get-ChildItem -LiteralPath $official -File | Sort-Object Name | ForEach-Object { "$($_.Name):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join "`n"
    Assert-Test ($before -ceq $after) 'Safety guard checks changed existing official assets.'
    Write-Host "Release safety: $count assertions passed (mock signatures; no signing or publication)."
} finally {
    if (Test-Path Function:\Move-SuiteDirectory) { Remove-Item Function:\Move-SuiteDirectory }
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^clipocr-release-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
