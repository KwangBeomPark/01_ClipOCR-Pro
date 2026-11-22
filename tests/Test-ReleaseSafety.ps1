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
    $remote = @([pscustomobject]@{ name = $names[0]; size = (Get-Item -LiteralPath $setup).Length; digest = 'sha256:' + (Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant(); state = 'uploaded' })
    $missing = @(Get-SuiteMissingAssets @($setup, $exe) $remote)
    Assert-Test ($missing.Count -eq 1 -and $missing[0] -eq $exe) 'Resume must return only missing assets.'
    $remote[0].digest = 'sha256:' + ('0' * 64)
    Expect-Failure { Get-SuiteMissingAssets @($setup) $remote } 'Remote digest conflict accepted.'
    Expect-Failure { Get-SuiteMissingAssets @($setup) @([pscustomobject]@{ name = $names[0]; size = 17 }) } 'Missing remote digest accepted.'
    Expect-Failure { Get-SuiteMissingAssets @($setup) @([pscustomobject]@{ name = $names[0]; size = (Get-Item -LiteralPath $setup).Length; digest = 'sha256:' + (Get-FileHash -LiteralPath $setup).Hash.ToLowerInvariant(); state = 'pending' }) } 'Pending remote state accepted.'
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
    $releaseText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\release.ps1') -Raw
    Assert-Test ($releaseText -notmatch 'Assert-SuiteRelease[^\r\n]*\.GetNewClosure\(\)') 'release.ps1 validation callback detaches from script-scoped ReleaseSafety functions.'
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
    function Get-ReparseSignature {
        param($Item)
        $linkType = if ($null -ne $Item.PSObject.Properties['LinkType'] -and $null -ne $Item.LinkType) { [string]$Item.LinkType } else { '' }
        $targetVal = if ($null -ne $Item.PSObject.Properties['LinkTarget'] -and $null -ne $Item.LinkTarget) {
            [string]$Item.LinkTarget
        } elseif ($null -ne $Item.PSObject.Properties['Target'] -and $null -ne $Item.Target) {
            (@($Item.Target) -join '|')
        } else { '' }
        if ([string]::IsNullOrWhiteSpace($targetVal)) {
            throw "Could not resolve reparse point target for snapshot: $($Item.FullName)"
        }
        return "$linkType|$($Item.Attributes)|$targetVal"
    }
    function Get-OfficialReleaseSnapshot {
        param([string]$Directory)
        try {
            $rootItem = Get-Item -LiteralPath $Directory -Force -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            return 'ABSENT'
        }
        if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return "LINK:$(Get-ReparseSignature $rootItem)"
        }
        if (-not $rootItem.PSIsContainer) {
            return "FILE:$((Get-FileHash -LiteralPath $rootItem.FullName -Algorithm SHA256).Hash)"
        }
        $prefix = $rootItem.FullName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $entries = [Collections.Generic.List[string]]::new()
        $queue = [Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($rootItem.FullName)
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            foreach ($child in @(Get-ChildItem -LiteralPath $current -Force)) {
                $rel = $child.FullName.Substring($prefix.Length)
                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    $entries.Add("L:$($rel):$(Get-ReparseSignature $child)")
                } elseif ($child.PSIsContainer) {
                    $entries.Add("D:$rel")
                    $queue.Enqueue($child.FullName)
                } else {
                    $entries.Add("F:$($rel):$((Get-FileHash -LiteralPath $child.FullName -Algorithm SHA256).Hash)")
                }
            }
        }
        if ($entries.Count -eq 0) { return 'EMPTY' }
        $sorted = [string[]]$entries.ToArray()
        [Array]::Sort($sorted, [StringComparer]::Ordinal)
        return ("EXISTS`n" + ($sorted -join "`n"))
    }
    Assert-Test ((Get-OfficialReleaseSnapshot (Join-Path $fixture 'absent-release')) -ceq 'ABSENT') 'Absent release directory snapshot failed.'
    $emptyRelease = Join-Path $fixture 'empty-release'
    New-Item -ItemType Directory -Path $emptyRelease | Out-Null
    Assert-Test ((Get-OfficialReleaseSnapshot $emptyRelease) -ceq 'EMPTY') 'Empty release directory snapshot failed.'
    $releaseSnap = Get-OfficialReleaseSnapshot $release
    $expectedSetupEntry = "F:$($names[0]):$((Get-FileHash -LiteralPath (Join-Path $release $names[0]) -Algorithm SHA256).Hash)"
    Assert-Test ($releaseSnap.StartsWith("EXISTS`n") -and (($releaseSnap -split "`n") -ccontains $expectedSetupEntry)) 'Populated release directory snapshot missed installer hash.'
    Expect-Failure { Get-ReparseSignature ([pscustomobject]@{ FullName = 'fixture-link'; Attributes = [IO.FileAttributes]::ReparsePoint }) } 'Unresolvable reparse point target was accepted.'
    $linkTargetA = Join-Path $fixture 'link-target-a'
    $linkTargetB = Join-Path $fixture 'link-target-b'
    New-Item -ItemType Directory -Path $linkTargetA, $linkTargetB | Out-Null
    [IO.File]::WriteAllText((Join-Path $linkTargetA 'secret.txt'), 'outside-target')
    $rootLink = Join-Path $fixture 'release-link'
    $nestedLink = Join-Path $emptyRelease 'nested-link'
    try {
        New-Item -ItemType Junction -Path $rootLink -Target $linkTargetA | Out-Null
        $linkSnapA = Get-OfficialReleaseSnapshot $rootLink
        [IO.Directory]::Delete($rootLink)
        New-Item -ItemType Junction -Path $rootLink -Target $linkTargetB | Out-Null
        $linkSnapB = Get-OfficialReleaseSnapshot $rootLink
        [IO.Directory]::Delete($rootLink)
        Assert-Test ($linkSnapA.StartsWith('LINK:') -and $linkSnapB.StartsWith('LINK:') -and ($linkSnapA -cne $linkSnapB)) 'Root reparse point target change was not detected.'

        New-Item -ItemType Junction -Path $nestedLink -Target $linkTargetA | Out-Null
        $nestedSnapA = Get-OfficialReleaseSnapshot $emptyRelease
        [IO.Directory]::Delete($nestedLink)
        New-Item -ItemType Junction -Path $nestedLink -Target $linkTargetB | Out-Null
        $nestedSnapB = Get-OfficialReleaseSnapshot $emptyRelease
        [IO.Directory]::Delete($nestedLink)
        Assert-Test (
            $nestedSnapA.StartsWith("EXISTS`n") -and
            $nestedSnapB.StartsWith("EXISTS`n") -and
            ($nestedSnapA -match '(?m)^L:nested-link:') -and
            ($nestedSnapB -match '(?m)^L:nested-link:') -and
            ($nestedSnapA -cne $nestedSnapB) -and
            ($nestedSnapA -notmatch 'secret\.txt') -and
            ($nestedSnapB -notmatch 'secret\.txt')
        ) 'Child reparse point retargeting or non-descent failed.'
    } finally {
        foreach ($junctionPath in @($rootLink, $nestedLink)) {
            if ($null -ne (Get-Item -LiteralPath $junctionPath -Force -ErrorAction SilentlyContinue)) {
                [IO.Directory]::Delete($junctionPath)
            }
        }
    }
    $guardRepo = Join-Path $fixture 'guard-repo'
    $guardScripts = Join-Path $guardRepo 'scripts'
    $guardOfficial = Join-Path $guardRepo 'release'
    New-Item -ItemType Directory -Path $guardScripts, $guardOfficial | Out-Null
    foreach ($scriptFile in @('Common.ps1', 'ReleaseSafety.ps1', 'build.ps1', 'release.ps1', 'publish.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\$scriptFile") -Destination (Join-Path $guardScripts $scriptFile)
    }
    [IO.File]::WriteAllText((Join-Path $guardOfficial $names[0]), 'official-sentinel-installer')
    [IO.File]::WriteAllText((Join-Path $guardOfficial 'build-manifest.json'), '{"sentinel":true}')
    [IO.File]::WriteAllText((Join-Path $guardOfficial 'SHA256SUMS.txt'), 'sentinel-checksum')
    $guardBefore = Get-OfficialReleaseSnapshot $guardOfficial
    $repoOfficial = Join-Path $repoRoot 'release'
    $repoBefore = Get-OfficialReleaseSnapshot $repoOfficial
    $guardFailures = [Collections.Generic.List[string]]::new()
    foreach ($guardCase in @(
        @{ Args = @('-File', (Join-Path $guardScripts 'build.ps1'), '-OutputDirectory', 'release'); Expected = 'Local build output must be inside build, dist or out' },
        @{ Args = @('-File', (Join-Path $guardScripts 'build.ps1'), '-OutputDirectory', 'release\nested'); Expected = 'Local build output must be inside build, dist or out' },
        @{ Args = @('-File', (Join-Path $guardScripts 'release.ps1'), '-SkipSigning'); Expected = 'official release cannot be unsigned' },
        @{ Args = @('-File', (Join-Path $guardScripts 'publish.ps1'), '-AllowUnsigned'); Expected = 'official publication cannot bypass verification' },
        @{ Args = @('-File', (Join-Path $guardScripts 'publish.ps1'), '-AllowLegacyTimestamp'); Expected = 'official publication cannot bypass verification' }
    )) {
        $result = Invoke-Native powershell.exe (@('-NoProfile', '-ExecutionPolicy', 'Bypass') + $guardCase.Args) -MergeStdErr
        $normalizedOutput = ($result.Text -replace '\s+', ' ')
        if ($result.ExitCode -eq 0 -or -not ($normalizedOutput -match [regex]::Escape($guardCase.Expected))) {
            $guardFailures.Add("Unsafe entry point was not rejected by its safety guard: $($guardCase.Args -join ' ')")
        } else {
            $script:count++
        }
    }
    $guardAfter = Get-OfficialReleaseSnapshot $guardOfficial
    $repoAfter = Get-OfficialReleaseSnapshot $repoOfficial
    Assert-Test ($guardBefore -ceq $guardAfter) 'Safety guard checks changed isolated official release assets.'
    Assert-Test ($repoBefore -ceq $repoAfter) 'Safety guard checks changed repository official release assets.'
    Assert-Test ($guardFailures.Count -eq 0) ($guardFailures -join '; ')
    Write-Host "Release safety: $count assertions passed (mock signatures; no signing or publication)."
} finally {
    if (Test-Path Function:\Move-SuiteDirectory) { Remove-Item Function:\Move-SuiteDirectory }
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^clipocr-release-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
