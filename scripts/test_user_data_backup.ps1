# Isolated executable regression checks for the common suite backup engine.
[CmdletBinding()]param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script = Join-Path $PSScriptRoot 'Manage-UserData.ps1'
$profile = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'user-data-profile.json') -Raw | ConvertFrom-Json
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $repo ('build\backup-test-' + [guid]::NewGuid().ToString('N'))
$settings = Join-Path $fixture 'app\UserSetting'
$null = New-Item -ItemType Directory -Path $settings -Force
$config = Join-Path $settings 'settings.json'
[IO.File]::WriteAllText($config,'{"saved":25,"language":"한국어"}',[Text.UTF8Encoding]::new($false))
$null = New-Item -ItemType Directory -Path (Join-Path $settings 'nested')
[IO.File]::WriteAllText((Join-Path $settings 'nested\Łódź.ini'),'original')
foreach ($folder in @($profile.optionalDataFolders)) {
    $null = New-Item -ItemType Directory -Path (Join-Path $settings $folder)
    [IO.File]::WriteAllText((Join-Path $settings ($folder + '\data.bin')),'work-data')
}
$script:assertions = 0
function Assert-Test([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:assertions++
}
function Assert-Rejected([scriptblock]$Operation,[string]$Message) {
    $failed = $false
    try { & $Operation | Out-Null } catch { $failed = $true }
    Assert-Test $failed $Message
}
$archive = Join-Path $fixture 'full.zip'
& $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive $archive | Out-Null
& $script -Action Verify -Archive $archive | Out-Null
Assert-Test (Test-Path -LiteralPath $archive) 'Backup was not created.'
$restored = Join-Path $fixture 'restored'
& $script -Action Restore -Archive $archive -Destination $restored | Out-Null
Assert-Test ((Get-FileHash -LiteralPath (Join-Path $restored 'UserSetting\settings.json')).Hash -eq (Get-FileHash -LiteralPath $config).Hash) 'Restore changed configuration.'
Assert-Test ([IO.File]::ReadAllText((Join-Path $restored 'UserSetting\nested\Łódź.ini')) -eq 'original') 'Unicode path was not restored.'
$archiveHash = (Get-FileHash -LiteralPath $archive).Hash
Assert-Rejected { & $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive $archive } 'Existing archive was overwritten.'
Assert-Test ((Get-FileHash -LiteralPath $archive).Hash -eq $archiveHash) 'Existing backup changed.'
Assert-Rejected { & $script -Action Restore -Archive $archive -Destination $restored } 'Existing destination was overwritten.'
Assert-Test ([IO.File]::ReadAllText($config) -eq '{"saved":25,"language":"한국어"}') 'Source user data changed.'
Assert-Rejected { & $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive (Join-Path $settings 'recursive.zip') } 'Backup inside UserSetting was accepted.'
Assert-Rejected { & $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive (Join-Path $fixture 'small.zip') -MaxBytes 1 } 'Size limit was ignored.'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture 'small.zip'))) 'Failed backup was published.'
$minimal = Join-Path $fixture 'settings-only.zip'
& $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive $minimal -SettingsOnly | Out-Null
$minimalDestination = Join-Path $fixture 'settings-only-restored'
& $script -Action Restore -Archive $minimal -Destination $minimalDestination | Out-Null
foreach ($folder in @($profile.optionalDataFolders)) { Assert-Test (-not (Test-Path -LiteralPath (Join-Path $minimalDestination ('UserSetting\' + $folder)))) 'SettingsOnly included optional work data.' }
function New-BadArchive([string]$Name,[string]$Member,[string]$Contents,[bool]$Replace) {
    $path = Join-Path $fixture $Name
    [IO.File]::Copy($archive,$path)
    $zip = [IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Update)
    try {
        if ($Replace) { $zip.GetEntry($Member).Delete() }
        $entry = $zip.CreateEntry($Member)
        $writer = New-Object IO.StreamWriter($entry.Open(),[Text.UTF8Encoding]::new($false))
        try { $writer.Write($Contents) } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    return $path
}
$extra = New-BadArchive 'extra.zip' 'extra.txt' 'unexpected' $false
Assert-Rejected { & $script -Action Verify -Archive $extra } 'Extra ZIP member was accepted.'
$duplicate = New-BadArchive 'duplicate.zip' 'UserSetting/settings.json' 'duplicate' $false
Assert-Rejected { & $script -Action Verify -Archive $duplicate } 'Duplicate ZIP member was accepted.'
$caseDuplicate = New-BadArchive 'case-duplicate.zip' 'UserSetting/SETTINGS.JSON' 'duplicate' $false
Assert-Rejected { & $script -Action Verify -Archive $caseDuplicate } 'Case-insensitive duplicate ZIP member was accepted.'
$lock = [IO.File]::Open($config,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try { Assert-Rejected { & $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive (Join-Path $fixture 'locked.zip') } 'Locked user data was accepted.' }
finally { $lock.Dispose() }
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture 'locked.zip'))) 'Locked data backup was published.'
function Get-CimInstance {
    [pscustomobject]@{Name='RenamedOrVersionedApp.v9.1.0.exe';ExecutablePath=(Join-Path $fixture 'app\RenamedOrVersionedApp.v9.1.0.exe')}
}
try { Assert-Rejected { & $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive (Join-Path $fixture 'running.zip') } 'Renamed or versioned running app was not detected.' }
finally { Remove-Item -LiteralPath 'Function:\Get-CimInstance' }
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture 'running.zip'))) 'Backup of a running renamed app was published.'
$corrupt = New-BadArchive 'corrupt.zip' 'UserSetting/settings.json' 'corrupted' $true
Assert-Rejected { & $script -Action Restore -Archive $corrupt -Destination (Join-Path $fixture 'bad-restore') } 'Corrupted data was restored.'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $fixture 'bad-restore'))) 'Corrupted restoration was promoted.'
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $reader = New-Object IO.StreamReader($zip.GetEntry('backup-manifest.json').Open())
    try { $metadata = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
} finally { $zip.Dispose() }
$metadata.appId = 'DifferentApp'
$wrong = New-BadArchive 'wrong-app.zip' 'backup-manifest.json' ($metadata | ConvertTo-Json -Depth 8) $true
Assert-Rejected { & $script -Action Verify -Archive $wrong } 'Wrong app identity was accepted.'
$metadata.appId = $profile.appId
$metadata.excludedFolders = @('undeclared-folder')
$wrongFullScope = New-BadArchive 'wrong-full-scope.zip' 'backup-manifest.json' ($metadata | ConvertTo-Json -Depth 8) $true
Assert-Rejected { & $script -Action Verify -Archive $wrongFullScope } 'Full backup with exclusions was accepted.'
$metadata.scope = 'settings-only'
$wrongMinimalScope = New-BadArchive 'wrong-minimal-scope.zip' 'backup-manifest.json' ($metadata | ConvertTo-Json -Depth 8) $true
Assert-Rejected { & $script -Action Verify -Archive $wrongMinimalScope } 'Incorrect settings-only scope was accepted.'
if (@($profile.optionalDataFolders).Count) {
    $metadata.excludedFolders = @($profile.optionalDataFolders)
    $wrongMinimalMembers = New-BadArchive 'wrong-minimal-members.zip' 'backup-manifest.json' ($metadata | ConvertTo-Json -Depth 8) $true
    Assert-Rejected { & $script -Action Verify -Archive $wrongMinimalMembers } 'Settings-only backup containing work data was accepted.'
}
Assert-Rejected { & $script -Action Verify -Archive $archive -MaxBytes 1 } 'Verify size limit was ignored.'
function New-UnsafeBackup([string]$Name,[string]$Member,[bool]$Linked) {
    $path = Join-Path $fixture $Name
    $zip = [IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try {
        $payload = [Text.Encoding]::UTF8.GetBytes('data')
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
        $entry = $zip.CreateEntry($Member)
        if ($Linked) { $entry.ExternalAttributes = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]0xA1FF0000L),0) }
        $output = $entry.Open()
        try { $output.Write($payload,0,$payload.Length) } finally { $output.Dispose() }
        $meta = @{schema=1;appId=$profile.appId;scope='full';excludedFolders=@();files=@(@{path=$Member;length=$payload.Length;sha256=$hash})}
        $writer = New-Object IO.StreamWriter($zip.CreateEntry('backup-manifest.json').Open(),[Text.UTF8Encoding]::new($false))
        try { $writer.Write(($meta | ConvertTo-Json -Depth 8)) } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    return $path
}
$unsafeMembers = @('UserSetting/../escape.ini','UserSetting/C:ads','UserSetting/CON.txt','UserSetting/trailing.','UserSetting\backslash.ini')
$index = 0
foreach ($member in $unsafeMembers) {
    $unsafe = New-UnsafeBackup ('unsafe-' + $index + '.zip') $member $false
    Assert-Rejected { & $script -Action Restore -Archive $unsafe -Destination (Join-Path $fixture ('unsafe-restore-' + $index)) } 'Unsafe path was accepted.'
    $index++
}
$linked = New-UnsafeBackup 'linked.zip' 'UserSetting/link.ini' $true
Assert-Rejected { & $script -Action Verify -Archive $linked } 'Linked archive member was accepted.'
$external = Join-Path $fixture 'external-data'
$null = New-Item -ItemType Directory -Path $external
$junction = Join-Path $settings 'linked-folder'
$null = New-Item -ItemType Junction -Path $junction -Target $external
Assert-Rejected { & $script -Action Backup -AppRoot (Join-Path $fixture 'app') -Archive (Join-Path $fixture 'junction.zip') } 'Source junction was accepted.'
Assert-Rejected { & $script -Action Restore -Archive $archive -Destination (Join-Path $junction 'restored') } 'Linked destination parent was accepted.'
$empty = Join-Path $fixture 'empty-app\UserSetting'
$null = New-Item -ItemType Directory -Path $empty -Force
$emptyArchive = Join-Path $fixture 'empty.zip'
& $script -Action Backup -AppRoot (Split-Path -Parent $empty) -Archive $emptyArchive | Out-Null
& $script -Action Restore -Archive $emptyArchive -Destination (Join-Path $fixture 'empty-restored') | Out-Null
Assert-Test (Test-Path -LiteralPath (Join-Path $fixture 'empty-restored\UserSetting') -PathType Container) 'Empty settings could not be restored.'
Write-Output "PASS: $script:assertions backup safety assertions. Isolated fixtures retained in build/."
