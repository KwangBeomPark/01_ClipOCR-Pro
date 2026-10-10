[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$project = Split-Path -Leaf $repo
$repository = "KwangBeomPark/$project"
$isApp08 = $project.StartsWith('08_')
$fixture = Join-Path $repo ('build\publish-tests-' + [guid]::NewGuid().ToString('N'))
$scripts = Join-Path $fixture 'scripts'
$releasePath = Join-Path $fixture 'release'
New-Item -ItemType Directory -Path $scripts,$releasePath,(Join-Path $fixture 'docs\release-notes') -Force | Out-Null
$installer = if ($project.StartsWith('01_')) { 'App01_ClipOCR-Pro_Setup_v1.0.0.exe' } elseif ($project.StartsWith('02_')) { 'App02_SwiftDeck_Setup_v1.0.0.exe' } else { 'App08_OutlookTemplate_Setup_v1.0.0.exe' }
$manifest = @{ signed=$true; timestampType='rfc3161'; signerThumbprint=('a'*40); signerSubject='Fixture'; signerIssuer='Fixture'; artifacts=@(@{name=$installer}) }
[IO.File]::WriteAllText((Join-Path $releasePath $installer), 'installer-fixture')
[IO.File]::WriteAllText((Join-Path $releasePath 'build-manifest.json'), ($manifest | ConvertTo-Json -Depth 8))
[IO.File]::WriteAllText((Join-Path $releasePath 'SHA256SUMS.txt'), 'checksum-fixture')
[IO.File]::WriteAllText((Join-Path $fixture 'docs\release-notes\v1.0.0.md'), 'Fixture reviewed notes')
Copy-Item -LiteralPath (Join-Path $repo 'scripts\publish.ps1') -Destination (Join-Path $scripts 'publish.ps1')
# Execute the unchanged production publisher and asset comparer. Replace only external
# git/gh and local signing/provenance boundaries; no native command is invoked.
$helperPath = (Join-Path $repo 'scripts\ReleaseSafety.ps1').Replace("'", "''")
$helper = ". '$helperPath'`r`n" + @'
function Assert-SuiteRelease { param($Directory,$Version,$Commit,$SourceDigest,[switch]$RequireClean) }
function Assert-SuiteOrigin { param($Directory,$Repository) }
function Get-SuiteSourceDigest { param($Directory) 'd' * 64 }
'@
[IO.File]::WriteAllText((Join-Path $scripts 'ReleaseSafety.ps1'), $helper, [Text.UTF8Encoding]::new($false))
$common = @'
function Get-AppVersion { param($Path) '1.0.0' }
function Resolve-RepoPath { param($Root,$Path) Join-Path $Root $Path }
function Test-GitWorkingTreeDirty { param($Root) $false }
function Get-GitHeadCommit { param($Root) 'c' * 40 }
function Get-BuildOutputPaths { param($Root) @{Manifest=(Join-Path $Root 'build-manifest.json'); Checksums=(Join-Path $Root 'SHA256SUMS.txt')} }
function New-MockAsset {
    param($Path)
    [pscustomobject]@{name=(Split-Path -Leaf $Path); size=(Get-Item -LiteralPath $Path).Length; digest=('sha256:' + (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()); state='uploaded'}
}
function Invoke-Native {
    param($File,$Arguments,[switch]$Quiet,[switch]$MergeStdErr)
    $s = $global:PublishFixtureState
    $lines = @()
    if ($File -eq 'git') {
        if ($Arguments[0] -eq 'branch') { $lines = @('main') }
        elseif ($Arguments[0] -eq 'remote') { $lines = @("https://github.com/$($s.Repository).git") }
        elseif ($Arguments[0] -eq 'ls-remote' -and $Arguments -contains 'refs/heads/main') { $lines = @(('c'*40) + "`trefs/heads/main") }
        elseif ($Arguments[0] -eq 'ls-remote' -and $s.TagCommit) { $lines = @($s.TagCommit + "`trefs/tags/v1.0.0^{}") }
        elseif ($Arguments[0] -eq 'push') { throw 'Publisher attempted a real source push.' }
    } elseif ($File -eq 'gh') {
        if ($Arguments[0] -eq 'api') { $lines = @('[' + $(if ($null -ne $s.Release) { '[' + ($s.Release | ConvertTo-Json -Depth 12 -Compress) + ']' } else { '[]' }) + ']') }
        elseif ($Arguments[0] -eq 'release') {
            $verb = $Arguments[1]
            if ($Arguments -notcontains '--repo') { throw 'Mutation has no explicit repository.' }
            $repoIndex = [Array]::IndexOf($Arguments, '--repo') + 1
            if ($Arguments[$repoIndex] -notin @($s.Repository, "github.com/$($s.Repository)")) { throw 'Mutation targets another repository.' }
            $s.Mutations.Add($verb)
            if ($verb -eq 'upload' -and $s.Scenario -eq 'upload-failure') { throw 'Injected transfer failure.' }
            if ($verb -eq 'create') {
                if ($Arguments -notcontains '--draft') { throw 'Create exposed an unverified public release.' }
                $paths = @($Arguments | Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) -and [IO.Path]::GetExtension($_) -in @('.exe','.json','.txt') })
                $s.Release = [pscustomobject]@{tag_name='v1.0.0'; target_commitish=('c'*40); draft=$true; prerelease=$false; assets=@($paths | ForEach-Object { New-MockAsset $_ })}
                if ($s.Scenario -eq 'create-failure') { $s.Release.assets=@($s.Release.assets[0..1]); throw 'Injected partial-create failure.' }
                if ($s.Scenario -eq 'pending-after-create') { $s.Release.assets[0].state='pending' }
            } elseif ($verb -eq 'upload') {
                foreach ($path in @($Arguments | Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) -and [IO.Path]::GetExtension($_) -in @('.exe','.json','.txt') })) { $s.Release.assets += (New-MockAsset $path) }
            } elseif ($verb -eq 'edit') {
                if ($Arguments -notcontains '--draft=false' -or $Arguments -notcontains '--latest') { throw 'Publication flags missing.' }
                $s.Release.draft=$false
                if ($s.Scenario -eq 'post-public-conflict') { $s.Release.assets[0].digest='sha256:' + ('f'*64) }
            } else { throw "Unexpected mutation $verb" }
        }
    } else { throw "Unexpected native command $File" }
    [pscustomobject]@{ExitCode=0; StdOut=@($lines); StdErr=@(); Text=($lines -join "`n")}
}
function Invoke-NativeChecked { param($File,$Arguments,$Description,[switch]$Quiet,$FailureHint) Invoke-Native $File $Arguments }
function Invoke-Git { param($Root,$Arguments,[switch]$Checked) Invoke-Native git $Arguments }
'@
[IO.File]::WriteAllText((Join-Path $scripts 'Common.ps1'), $common, [Text.UTF8Encoding]::new($false))
. (Join-Path $scripts 'Common.ps1')
$passed = 0
function Check($Condition,$Message) { if (-not $Condition) { throw $Message }; $script:passed++ }
$names = @($installer,'build-manifest.json','SHA256SUMS.txt')
foreach ($scenario in @('new-public','new-draft','new-whatif','resume-complete','resume-whatif','resume-missing','resume-missing-whatif','public-existing','wrong-tag','wrong-draft-target','branch-draft-target','no-tag-exact-target','remote-extra','remote-duplicate','remote-pending','remote-size','remote-digest','draft-prerelease','create-failure','upload-failure','pending-after-create','post-public-conflict')) {
    $isNew = $scenario -in @('new-public','new-draft','new-whatif','create-failure','pending-after-create')
    $remote = if ($isNew) { $null } else { [pscustomobject]@{tag_name='v1.0.0'; target_commitish=('c'*40); draft=$true; prerelease=$false; assets=@($names | ForEach-Object { New-MockAsset (Join-Path $releasePath $_) })} }
    $global:PublishFixtureState = [pscustomobject]@{Repository=$repository; Scenario=$scenario; Release=$remote; TagCommit=$(if($isNew){$null}else{'c'*40}); Mutations=[Collections.Generic.List[string]]::new()}
    if ($scenario -in @('resume-missing','resume-missing-whatif','upload-failure')) { $remote.assets=@($remote.assets[0..1]) }
    if ($scenario -eq 'public-existing') { $remote.draft=$false }
    if ($scenario -eq 'wrong-tag') { $global:PublishFixtureState.TagCommit='f'*40 }
    if ($scenario -in @('wrong-draft-target','branch-draft-target','no-tag-exact-target')) { $global:PublishFixtureState.TagCommit=$null }
    if ($scenario -eq 'wrong-draft-target') { $remote.target_commitish='f'*40 }
    if ($scenario -eq 'branch-draft-target') { $remote.target_commitish='main' }
    if ($scenario -eq 'remote-extra') { $remote.assets += [pscustomobject]@{name='unexpected.zip';state='uploaded'} }
    if ($scenario -eq 'remote-duplicate') { $remote.assets += $remote.assets[0] }
    if ($scenario -eq 'remote-pending') { $remote.assets[0].state='pending' }
    if ($scenario -eq 'remote-size') { $remote.assets[0].size++ }
    if ($scenario -eq 'remote-digest') { $remote.assets[0].digest='sha256:' + ('f'*64) }
    if ($scenario -eq 'draft-prerelease') { $remote.prerelease=$true }
    $options = @{Confirm=$false}
    if (-not $isNew) { $options.Resume=$true }
    if ($scenario -like '*whatif') { $options.WhatIf=$true }
    if ($isApp08) { if ($scenario -ne 'new-draft') { $options.Publish=$true } } elseif ($scenario -eq 'new-draft') { $options.Draft=$true }
    $failed = $false
    try { & (Join-Path $scripts 'publish.ps1') @options | Out-Null } catch { $failed=$true; Write-Host "$scenario rejected: $($_.Exception.Message)" }
    $expectFailure = $scenario -in @('public-existing','wrong-tag','wrong-draft-target','branch-draft-target','remote-extra','remote-duplicate','remote-pending','remote-size','remote-digest','draft-prerelease','create-failure','upload-failure','pending-after-create','post-public-conflict')
    Check ($failed -eq $expectFailure) "Unexpected result in $scenario (failed=$failed)"
    $mutations = $global:PublishFixtureState.Mutations
    if ($scenario -like '*whatif' -or ($expectFailure -and $scenario -notin @('create-failure','upload-failure','pending-after-create','post-public-conflict'))) { Check ($mutations.Count -eq 0) "Mutation during rejected/WhatIf scenario $scenario : $mutations" }
    elseif ($scenario -eq 'new-draft') { Check (($mutations -join ',') -eq 'create' -and $global:PublishFixtureState.Release.draft) 'Draft-only request published' }
    elseif ($scenario -in @('create-failure','upload-failure','pending-after-create')) { Check ($mutations -notcontains 'edit') "Transfer failure published $scenario"; if ($scenario -eq 'create-failure') { Check ($global:PublishFixtureState.Release.draft -and @($global:PublishFixtureState.Release.assets).Count -eq 2) 'Partial draft was not preserved' } }
    elseif (-not $expectFailure) { Check ($mutations -contains 'edit' -and @($global:PublishFixtureState.Release.assets).Count -eq 3 -and -not $global:PublishFixtureState.Release.draft) "Valid scenario did not publish exact set: $scenario" }
    if ($scenario -eq 'resume-missing') { Check (($mutations -join ',') -eq 'upload,edit') 'Resume did not upload only missing assets before publication' }
}
Remove-Variable -Name PublishFixtureState -Scope Global
Write-Host "PASS: $passed publisher orchestration checks (mock git/gh/signature boundaries; no network, signing, installation or publication). Fixture retained: $fixture"
