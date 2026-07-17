function Reset-BranchlineQueryCache {
    $script:AppState.QueryCache = @{}
    $script:AppState.QueryCacheBytes = 0
    $script:AppState.RemoteSnapshotCache = $null
    $script:AppState.RemoteSnapshotKey = ""
}

function Remove-BranchlineCacheEntry {
    param([string]$Name)
    if ($null -eq $script:AppState.QueryCache -or -not $script:AppState.QueryCache.ContainsKey($Name)) { return }
    $entry = $script:AppState.QueryCache[$Name]
    $size = if ($null -ne $entry -and $null -ne $entry.PSObject.Properties["sizeBytes"]) { [int64]$entry.sizeBytes } else { 0 }
    [void]$script:AppState.QueryCache.Remove($Name)
    $script:AppState.QueryCacheBytes = [Math]::Max(0, [int64]$script:AppState.QueryCacheBytes - $size)
}

function Get-BranchlineCacheEntry {
    param([string]$Name, [string]$Key, [int]$MaximumAgeMilliseconds = 0)
    if ($null -eq $script:AppState.QueryCache -or -not $script:AppState.QueryCache.ContainsKey($Name)) { return $null }
    $entry = $script:AppState.QueryCache[$Name]
    if ($null -eq $entry -or [string]$entry.key -cne $Key) { return $null }
    if ($MaximumAgeMilliseconds -gt 0) {
        $age = ([DateTime]::UtcNow - [DateTime]$entry.createdAtUtc).TotalMilliseconds
        if ($age -gt $MaximumAgeMilliseconds) { return $null }
    }
    return $entry.value
}

function Set-BranchlineCacheEntry {
    param([string]$Name, [string]$Key, [object]$Value, [int64]$SizeBytes = 65536)
    $size = [Math]::Max(1024, $SizeBytes)
    Remove-BranchlineCacheEntry -Name $Name
    $limit = [int64]$script:AppState.QueryCacheLimitBytes
    if ($size -gt $limit) { return $Value }
    if (([int64]$script:AppState.QueryCacheBytes + $size) -gt $limit) {
        foreach ($candidate in @("local-files", "remote-files", "summary")) { Remove-BranchlineCacheEntry -Name $candidate }
    }
    if (([int64]$script:AppState.QueryCacheBytes + $size) -le $limit) {
        $script:AppState.QueryCache[$Name] = [pscustomobject]@{ key = $Key; value = $Value; sizeBytes = $size; createdAtUtc = [DateTime]::UtcNow }
        $script:AppState.QueryCacheBytes = [int64]$script:AppState.QueryCacheBytes + $size
    }
    return $Value
}

function Get-CachedRepositoryValue {
    param([string]$Name, [string]$Key, [scriptblock]$Factory, [int64]$SizeBytes = 65536)
    $cached = Get-BranchlineCacheEntry -Name $Name -Key $Key
    if ($null -ne $cached) { return $cached }
    $value = & $Factory
    Set-BranchlineCacheEntry -Name $Name -Key $Key -Value $value -SizeBytes $SizeBytes | Out-Null
    return $value
}

function Get-OpaqueRevision {
    param([AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($(if ($null -eq $Value) { "" } else { $Value }))
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-RepositoryMetadataPaths {
    param([string]$RepoPath)
    $root = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')
    $cached = Get-BranchlineCacheEntry -Name "git-metadata" -Key $root
    if ($null -ne $cached) { return $cached }
    $dotGit = Join-Path $root ".git"
    $gitDirectory = ""
    if (Test-Path -LiteralPath $dotGit -PathType Container) {
        $gitDirectory = [System.IO.Path]::GetFullPath($dotGit).TrimEnd('\')
    }
    elseif (Test-Path -LiteralPath $dotGit -PathType Leaf) {
        $pointer = ([System.IO.File]::ReadAllText($dotGit)).Trim()
        if ($pointer -notmatch '^gitdir:\s*(.+)$') { throw "The repository's Git metadata pointer is invalid." }
        $target = $Matches[1].Trim()
        if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $root $target }
        $gitDirectory = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
    }
    if ([string]::IsNullOrWhiteSpace($gitDirectory) -or -not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
        throw "Branchline could not locate this repository's Git metadata."
    }
    $commonDirectory = $gitDirectory
    $commonPointer = Join-Path $gitDirectory "commondir"
    if (Test-Path -LiteralPath $commonPointer -PathType Leaf) {
        $target = ([System.IO.File]::ReadAllText($commonPointer)).Trim()
        if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $gitDirectory $target }
        $commonDirectory = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
    }
    $value = [pscustomobject]@{ gitDirectory = $gitDirectory; commonDirectory = $commonDirectory }
    Set-BranchlineCacheEntry -Name "git-metadata" -Key $root -Value $value -SizeBytes 4096 | Out-Null
    return $value
}

function Get-FileMetadataRevision {
    param([string[]]$Paths)
    $records = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            $records.Add("F|$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)")
        }
        elseif (Test-Path -LiteralPath $path -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction Stop | Sort-Object FullName)) {
                $records.Add("F|$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)")
            }
        }
        else { $records.Add("M|$path") }
    }
    return Get-OpaqueRevision ($records -join "`n")
}

function Get-RepositoryRevisions {
    param([string]$RepoPath, [object]$WorkingState)
    $metadata = Get-RepositoryMetadataPaths $RepoPath
    $configRevision = Get-FileMetadataRevision @(
        (Join-Path $metadata.commonDirectory "config"),
        (Join-Path $metadata.gitDirectory "config.worktree")
    )
    $packedRefs = Join-Path $metadata.commonDirectory "packed-refs"
    $localRefsRevision = Get-FileMetadataRevision @((Join-Path $metadata.commonDirectory "refs\heads"), $packedRefs)
    $remoteRefsRevision = Get-FileMetadataRevision @((Join-Path $metadata.commonDirectory "refs\remotes\origin"), $packedRefs)
    return [pscustomobject][ordered]@{
        repository = Get-OpaqueRevision (([System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')) + "|" + $metadata.gitDirectory)
        local = [string]$WorkingState.signature
        head = Get-OpaqueRevision (([string]$WorkingState.headState) + "|" + ([string]$WorkingState.branch) + "|" + ([string]$WorkingState.headCommit))
        config = $configRevision
        localRefs = $localRefsRevision
        remoteRefs = $remoteRefsRevision
    }
}

function Clear-BranchlineCachesForScope {
    param([object]$Scope)
    if ($null -eq $Scope) { return }
    if ([bool]$Scope.full) { Reset-BranchlineQueryCache; return }
    if ([bool]$Scope.local) {
        foreach ($name in @("local-status", "local-files", "summary")) { Remove-BranchlineCacheEntry $name }
    }
    if ([bool]$Scope.history) {
        foreach ($name in @("commits", "tracking", "summary")) { Remove-BranchlineCacheEntry $name }
    }
    if ([bool]$Scope.branches) {
        foreach ($name in @("branches", "tracking", "remote-files", "summary")) { Remove-BranchlineCacheEntry $name }
    }
    if ([bool]$Scope.remote) {
        foreach ($name in @("tracking", "remote-files", "summary")) { Remove-BranchlineCacheEntry $name }
        $script:AppState.RemoteSnapshotCache = $null
        $script:AppState.RemoteSnapshotKey = ""
    }
    if ([string]$script:AppState.CurrentAction -in @("setIdentity")) {
        foreach ($name in @("identity", "summary")) { Remove-BranchlineCacheEntry $name }
    }
}

function Get-RepositoryHealthSnapshot {
    param([string]$RepoPath, [switch]$Force)

    $working = Get-WorkingTreeState $RepoPath -Force:$Force
    $head = if ($working.ok) {
        [pscustomobject]@{ state = [string]$working.headState; branch = [string]$working.branch; commit = [string]$working.headCommit }
    }
    else { [pscustomobject]@{ state = "error"; branch = ""; commit = "" } }
    $errors = @($(if (-not $working.ok) { [string]$working.error })) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    return [pscustomobject]@{
        ok = (@($errors).Count -eq 0)
        error = (@($errors) -join "`n")
        working = $working
        head = $head
        operation = Get-GitOperationState $RepoPath
    }
}
