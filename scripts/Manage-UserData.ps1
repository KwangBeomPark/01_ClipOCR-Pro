# Shared suite backup engine. Windows PowerShell 5.1 and PowerShell 7.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Backup','Verify','Restore')][string]$Action,
    [string]$AppRoot,
    [Parameter(Mandatory=$true)][string]$Archive,
    [string]$Destination,
    [switch]$SettingsOnly,
    [ValidateRange(1,1099511627776)][long]$MaxBytes = 10737418240
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$profile = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'user-data-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Assert-PlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked paths are not supported: $cursor" }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
function Assert-Member([string]$Name) {
    if (-not $Name.StartsWith('UserSetting/',[StringComparison]::Ordinal) -or $Name.Contains('\')) { throw "Invalid backup member: $Name" }
    foreach ($part in $Name.Split('/')) {
        if (-not $part -or $part -eq '.' -or $part -eq '..' -or $part -match '[<>:"|?*\x00-\x1f]' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "Unsafe backup member: $Name" }
    }
}
function Copy-LimitedStream([IO.Stream]$Source,[IO.Stream]$Target,[long]$Limit) {
    $buffer = New-Object byte[] 65536
    [long]$count = 0
    while (($read = $Source.Read($buffer,0,$buffer.Length)) -gt 0) {
        if ($read -gt ($Limit - $count)) { throw 'Backup stream exceeded the declared size limit.' }
        $Target.Write($buffer,0,$read)
        $count += $read
    }
}
function Get-StreamHash([IO.Stream]$Stream,[long]$Limit = $MaxBytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $buffer = New-Object byte[] 65536
        [long]$count = 0
        while (($read = $Stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            if ($read -gt ($Limit - $count)) { throw 'Backup stream exceeded the declared size limit.' }
            $null = $sha.TransformBlock($buffer,0,$read,$buffer,0)
            $count += $read
        }
        $null = $sha.TransformFinalBlock($buffer,0,0)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}
function Assert-AppClosed([string]$Root) {
    $prefix = $Root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    foreach ($proc in Get-CimInstance Win32_Process) {
        # Executable identity can change during updates or portable renaming.
        if ($proc.ExecutablePath -and $proc.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Close all processes running from the selected app folder before backing up." }
        if (@($profile.executableNames) -contains $proc.Name) {
            if (-not $proc.ExecutablePath) { throw "Close $($profile.displayName) before backing up; its running process cannot be inspected." }
            if ($proc.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Close $($profile.displayName) before backing up." }
        }
        elseif ($profile.appId -eq 'App04_DataRefinery' -and $proc.Name -match '^App04_DataRefinery_v[0-9]+\.[0-9]+\.[0-9]+\.exe$') {
            if (-not $proc.ExecutablePath -or $proc.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Close Data Refinery before backing up.' }
        }
    }
}
function Get-UserFiles([string]$Root) {
    $queue = New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue((Join-Path $Root 'UserSetting'))
    while ($queue.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked user data is not supported: $($item.Name)" }
            $relative = $item.FullName.Substring($Root.TrimEnd('\').Length + 1).Replace('\','/')
            $excluded = $false
            if ($SettingsOnly) {
                foreach ($folder in @($profile.optionalDataFolders)) {
                    if ($relative.Equals('UserSetting/' + $folder,[StringComparison]::OrdinalIgnoreCase) -or $relative.StartsWith('UserSetting/' + $folder + '/',[StringComparison]::OrdinalIgnoreCase)) { $excluded = $true }
                }
            }
            if ($excluded) { continue }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) } else { $item.FullName }
        }
    }
}
function Read-VerifiedBackup([string]$Path) {
    Assert-PlainPath $Path
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if ($zip.Entries.Count -gt 100001) { throw 'Too many backup members.' }
        $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            if (-not $names.Add($entry.FullName)) { throw 'Duplicate backup members.' }
            if (($entry.ExternalAttributes -band 0xF0000000L) -eq 0xA0000000L) { throw 'Linked backup members are not allowed.' }
        }
        $metadata = $zip.GetEntry('backup-manifest.json')
        if (-not $metadata -or $metadata.Length -gt 8388608) { throw 'Missing or oversized backup manifest.' }
        $metadataStream = $metadata.Open()
        $memory = New-Object IO.MemoryStream
        try { Copy-LimitedStream $metadataStream $memory 8388608; $manifest = [Text.Encoding]::UTF8.GetString($memory.ToArray()) | ConvertFrom-Json }
        finally { $memory.Dispose(); $metadataStream.Dispose() }
        if ($manifest.schema -ne 1 -or $manifest.appId -cne $profile.appId -or $manifest.scope -notin @('full','settings-only')) { throw 'This backup belongs to a different app or format.' }
        $excluded = @($manifest.excludedFolders)
        if ($manifest.scope -eq 'full' -and $excluded.Count) { throw 'Full backups cannot declare excluded data folders.' }
        if ($manifest.scope -eq 'settings-only') {
            $expectedExcluded = @($profile.optionalDataFolders | Sort-Object)
            $actualExcluded = @($excluded | Sort-Object)
            if ($expectedExcluded.Count -ne $actualExcluded.Count -or ($expectedExcluded -join '/') -cne ($actualExcluded -join '/')) { throw 'Settings-only exclusion scope does not match this app.' }
        }
        $members = @($manifest.files)
        if ($members.Count + 1 -ne $zip.Entries.Count) { throw 'Unexpected or missing backup members.' }
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        [long]$total = 0
        foreach ($file in $members) {
            Assert-Member $file.path
            if ($manifest.scope -eq 'settings-only') {
                foreach ($folder in @($profile.optionalDataFolders)) {
                    if ($file.path.Equals('UserSetting/' + $folder,[StringComparison]::OrdinalIgnoreCase) -or $file.path.StartsWith('UserSetting/' + $folder + '/',[StringComparison]::OrdinalIgnoreCase)) { throw 'Settings-only backup includes excluded work data.' }
                }
            }
            if (-not $seen.Add($file.path) -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $file.length -lt 0) { throw 'Invalid backup file record.' }
            $entry = $zip.GetEntry($file.path)
            if (-not $entry -or $entry.Length -ne $file.length -or $entry.Length -gt ($MaxBytes - $total)) { throw 'Backup size limit exceeded or size mismatch.' }
            $total += $entry.Length
            $stream = $entry.Open()
            try { $hash = Get-StreamHash $stream $entry.Length } finally { $stream.Dispose() }
            if ($hash -cne $file.sha256) { throw "Backup checksum mismatch: $($file.path)" }
        }
        return $manifest
    }
    finally { $zip.Dispose() }
}

$Archive = [IO.Path]::GetFullPath($Archive)
if ($Action -eq 'Verify') {
    $manifest = Read-VerifiedBackup $Archive
    Write-Output "Verified $($profile.displayName) backup: $(@($manifest.files).Count) files; scope $($manifest.scope)."
    return
}
if ($Action -eq 'Backup') {
    if (-not $AppRoot) { $AppRoot = Join-Path $env:LOCALAPPDATA ('Programs\' + $profile.installFolder) }
    $AppRoot = [IO.Path]::GetFullPath($AppRoot)
    $settings = Join-Path $AppRoot 'UserSetting'
    Assert-PlainPath $settings
    Assert-PlainPath $Archive
    if (-not (Test-Path -LiteralPath $settings -PathType Container)) { throw 'UserSetting was not found. Specify the active installed or portable AppRoot.' }
    if (Test-Path -LiteralPath $Archive) { throw 'The backup already exists. Choose a new archive name.' }
    if ($Archive.StartsWith($settings.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Store the backup outside UserSetting.' }
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($Archive)) -PathType Container)) { throw 'Create the backup parent folder first.' }
    Assert-AppClosed $AppRoot
    $paths = @(Get-UserFiles $AppRoot)
    $tmp = $Archive + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $stream = [IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $zip = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    $records = New-Object 'Collections.Generic.List[object]'
    [long]$total = 0
    try {
        foreach ($path in ($paths | Sort-Object)) {
            $relative = $path.Substring($AppRoot.TrimEnd('\').Length + 1).Replace('\','/')
            Assert-Member $relative
            $excluded = $false
            if ($SettingsOnly) {
                foreach ($folder in @($profile.optionalDataFolders)) { if ($relative.StartsWith('UserSetting/' + $folder + '/',[StringComparison]::OrdinalIgnoreCase)) { $excluded = $true } }
            }
            if ($excluded) { continue }
            $sourceStream = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                if ($sourceStream.Length -gt ($MaxBytes - $total)) { throw 'Backup size limit exceeded. Increase MaxBytes or select SettingsOnly.' }
                $length = $sourceStream.Length
                $hash = Get-StreamHash $sourceStream
                $sourceStream.Position = 0
                $entry = $zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
                $output = $entry.Open()
                try { Copy-LimitedStream $sourceStream $output $length } finally { $output.Dispose() }
                $records.Add([ordered]@{path=$relative;length=$length;sha256=$hash})
                $total += $length
            } finally { $sourceStream.Dispose() }
        }
        $scope = 'full'; if ($SettingsOnly) { $scope = 'settings-only' }
        $manifest = [ordered]@{schema=1;appId=$profile.appId;createdUtc=[DateTime]::UtcNow.ToString('o');scope=$scope;excludedFolders=@();externalData=@($profile.externalData);files=@($records.ToArray())}
        if ($SettingsOnly) { $manifest.excludedFolders = @($profile.optionalDataFolders) }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 8))
        $entry = $zip.CreateEntry('backup-manifest.json')
        $output = $entry.Open()
        try { $output.Write($bytes,0,$bytes.Length) } finally { $output.Dispose() }
    }
    finally { $zip.Dispose(); $stream.Flush($true); $stream.Dispose() }
    $null = Read-VerifiedBackup $tmp
    Assert-AppClosed $AppRoot
    $currentPaths = @(Get-UserFiles $AppRoot)
    if ($currentPaths.Count -ne $records.Count) { throw 'User data changed during backup. Close the app and retry with a new archive name.' }
    foreach ($record in $records) {
        $current = Join-Path $AppRoot $record.path.Replace('/',[IO.Path]::DirectorySeparatorChar)
        Assert-PlainPath $current
        if (-not (Test-Path -LiteralPath $current -PathType Leaf) -or (Get-Item -LiteralPath $current).Length -ne $record.length -or (Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256) { throw 'User data changed during backup. The verified archive was not published.' }
    }
    [IO.File]::Move($tmp,$Archive)
    Write-Output "Created verified $($profile.displayName) backup: $($records.Count) files; scope $scope. Keep the archive private."
    return
}

# Restore never merges into an existing directory or replaces user files.
if (-not $Destination) { throw 'Specify a new, nonexistent Destination folder for restoration.' }
$Destination = [IO.Path]::GetFullPath($Destination)
Assert-PlainPath $Destination
if (Test-Path -LiteralPath $Destination) { throw 'Destination already exists. Restore to a new folder and retain the current UserSetting.' }
$parent = [IO.Path]::GetDirectoryName($Destination)
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Create the destination parent folder first.' }
$manifest = Read-VerifiedBackup $Archive
$stage = Join-Path $parent ('.suite-restore-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory((Join-Path $stage 'UserSetting'))
$zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
    foreach ($file in @($manifest.files)) {
        Assert-Member $file.path
        $target = Join-Path $stage $file.path.Replace('/',[IO.Path]::DirectorySeparatorChar)
        Assert-PlainPath $target
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        $sourceStream = $zip.GetEntry($file.path).Open()
        $output = [IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { Copy-LimitedStream $sourceStream $output $file.length; $output.Flush($true) } finally { $output.Dispose(); $sourceStream.Dispose() }
        if ((Get-Item -LiteralPath $target).Length -ne $file.length -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { throw 'Restored file checksum mismatch; the staging folder was retained.' }
    }
} finally { $zip.Dispose() }
Assert-PlainPath $Destination
try { [IO.Directory]::Move($stage,$Destination) }
catch { throw "Restore could not be promoted. Existing data was preserved; verified staging remains at: $stage. $($_.Exception.Message)" }
Write-Output "Restored verified $($profile.displayName) data into a new folder. Existing settings were preserved. Scope: $($manifest.scope)."
