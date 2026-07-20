Set-StrictMode -Version 2.0

$script:MaxOutputCharacters = 1048576
$script:MaxPreviewBytes = 524288
$script:MaxHeaderBytes = 16384
$script:MaxBodyBytes = 1048576
$script:AppState = [ordered]@{
    Port = 4848
    RepoPath = ""
    SelectedPath = ""
    Token = ""
    GitPath = ""
    WebRoot = ""
    ProjectRoot = ""
    InstallId = ""
    Version = "0.0.0"
    ProtocolVersion = 1
    IndexHtml = ""
    StylesCss = ""
    AppJavaScript = ""
    ExtraAssets = @{}
    ConfigPath = ""
    RuntimePath = ""
    LocalScannedAt = ""
    RemoteFetchedAt = ""
    LocalStatusSignature = ""
    RemoteSnapshotCache = $null
    RemoteSnapshotKey = ""
    QueryCache = @{}
    QueryCacheBytes = 0
    QueryCacheLimitBytes = 33554432
    CurrentAction = ""
    ProcessStartedAtUtc = ""
    RuntimeStateCheckedAt = [DateTime]::MinValue
    StartupMessage = "Choose a trusted Git repository to begin."
    Busy = $false
    AllowLocalTestRemote = $false
}

$repositoryActionsPath = Join-Path $PSScriptRoot "private\RepositoryActions.ps1"
if (-not (Test-Path -LiteralPath $repositoryActionsPath -PathType Leaf)) { throw "Branchline action helpers are missing." }
. $repositoryActionsPath

function Limit-Text {
    param([string]$Text, [int]$Limit = $script:MaxOutputCharacters)
    if ($null -eq $Text) { return "" }
    if ($Text.Length -le $Limit) { return $Text }
    return $Text.Substring(0, $Limit) + "`n`n[Output truncated after $Limit characters.]"
}

function Join-CommandOutput {
    param([object[]]$Parts)
    return (@($Parts | ForEach-Object {
        if ($null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_)) {
            ([string]$_).Trim()
        }
    }) -join "`n`n").Trim()
}

function Get-PayloadString {
    param([object]$Payload, [string]$Name)
    if ($null -eq $Payload) { return "" }
    $property = $Payload.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return "" }
    return [string]$property.Value
}

function New-SessionToken {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return ([Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_"))
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) { return '""' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0

    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes += 1
            continue
        }

        if ($character -eq '"') {
            if ($backslashes -gt 0) {
                [void]$builder.Append(('\' * ($backslashes * 2)))
                $backslashes = 0
            }
            [void]$builder.Append('\"')
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

$gitProcessPath = Join-Path $PSScriptRoot "private\GitProcess.ps1"
if (-not (Test-Path -LiteralPath $gitProcessPath -PathType Leaf)) { throw "Branchline Git process helpers are missing." }
. $gitProcessPath

function Resolve-SafeDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Choose a local folder first."
    }

    $item = Get-Item -LiteralPath $Path.Trim() -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) {
        throw "The selected path is not a folder."
    }

    $rawFullPath = [System.IO.Path]::GetFullPath($item.FullName)
    $fullPath = $rawFullPath.TrimEnd('\')
    $blockedExact = New-Object System.Collections.Generic.List[string]
    $blockedTrees = New-Object System.Collections.Generic.List[string]
    $driveRoot = [System.IO.Path]::GetPathRoot($rawFullPath)
    if (-not [string]::IsNullOrWhiteSpace($driveRoot)) {
        $blockedExact.Add($driveRoot.TrimEnd('\'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $blockedExact.Add([System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\'))
    }
    foreach ($protectedPath in @($env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) {
        if (-not [string]::IsNullOrWhiteSpace($protectedPath)) {
            $blockedTrees.Add([System.IO.Path]::GetFullPath($protectedPath).TrimEnd('\'))
        }
    }

    foreach ($blockedPath in $blockedExact) {
        if ($fullPath.Equals($blockedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "For safety, choose a project folder rather than a drive, Windows folder, program folder, or profile root."
        }
    }
    foreach ($blockedPath in $blockedTrees) {
        if ($fullPath.Equals($blockedPath, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($blockedPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "For safety, project folders cannot be inside Windows, Program Files, or ProgramData."
        }
    }

    $cursor = $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $cursorItem = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($cursorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "For safety, choose a project folder that does not pass through a junction or symbolic link: $cursor"
        }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = $parent
    }

    return $fullPath
}

function Test-GitRepository {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    $result = Invoke-GitCommand -WorkingDirectory $Path -Arguments @("rev-parse", "--is-inside-work-tree") -DisplayCommand "check repository" -TimeoutSeconds 10 -ReadOnly
    return ($result.ok -and $result.raw.Trim() -eq "true")
}

function Get-GitRepositoryRoot {
    param([string]$Path)
    if (-not (Test-GitRepository $Path)) { return "" }
    $result = Invoke-GitCommand -WorkingDirectory $Path -Arguments @("rev-parse", "--show-toplevel") -DisplayCommand "locate repository root" -TimeoutSeconds 10 -ReadOnly
    if (-not $result.ok -or [string]::IsNullOrWhiteSpace($result.raw)) { return "" }
    return [System.IO.Path]::GetFullPath($result.raw.Trim()).TrimEnd('\')
}

function Get-GitMetadataBackups {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\.branchline-git-backup-\d{8}-\d{6}(?:-\d+)?$' } |
        Sort-Object Name -Descending |
        ForEach-Object { [pscustomobject]@{ name = $_.Name; created = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } })
}

function Get-FolderState {
    param([string]$Path, [object]$KnownIsRepo = $null)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{ selected = $false; path = ""; name = ""; isRepo = $false; empty = $false; detachable = $false; backups = @() }
    }
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    $gitMetadata = Join-Path $Path ".git"
    return [pscustomobject]@{
        selected = $true
        path = $Path
        name = Split-Path -Leaf $Path
        isRepo = if ($null -ne $KnownIsRepo) { [bool]$KnownIsRepo } else { Test-GitRepository $Path }
        empty = ($items.Count -eq 0)
        detachable = (Test-Path -LiteralPath $gitMetadata -PathType Container)
        backups = @(Get-GitMetadataBackups $Path)
    }
}

function Save-LastRepository {
    if ([string]::IsNullOrWhiteSpace($script:AppState.ConfigPath)) { return }
    try {
        $directory = Split-Path -Parent $script:AppState.ConfigPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }
        @{ repoPath = $script:AppState.RepoPath; selectedPath = $script:AppState.SelectedPath } | ConvertTo-Json | Set-Content -LiteralPath $script:AppState.ConfigPath -Encoding UTF8
    }
    catch {
        Write-Warning "Could not save the last repository path."
    }
}

function Get-SavedRepository {
    if ([string]::IsNullOrWhiteSpace($script:AppState.ConfigPath) -or -not (Test-Path -LiteralPath $script:AppState.ConfigPath -PathType Leaf)) {
        return ""
    }
    try {
        $config = Get-Content -Raw -LiteralPath $script:AppState.ConfigPath -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.repoPath) { return [string]$config.repoPath }
    }
    catch {
        return ""
    }
    return ""
}

function Get-SavedFolder {
    if ([string]::IsNullOrWhiteSpace($script:AppState.ConfigPath) -or -not (Test-Path -LiteralPath $script:AppState.ConfigPath -PathType Leaf)) { return "" }
    try {
        $config = Get-Content -Raw -LiteralPath $script:AppState.ConfigPath -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.selectedPath) { return [string]$config.selectedPath }
        if ($null -ne $config.repoPath) { return [string]$config.repoPath }
    }
    catch { return "" }
    return ""
}

function Test-GitHubName {
    param([string]$Owner, [string]$Repository)
    return ($Owner -match '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$' -and $Repository -match '^[A-Za-z0-9_.-]{1,100}$')
}

function ConvertTo-GitHubRemoteValue {
    param([string]$Value, [switch]$AllowLocal)

    $invalid = [pscustomobject]@{ valid = $false; type = "invalid"; gitUrl = ""; webUrl = ""; display = ""; owner = ""; repository = ""; message = "Enter a GitHub HTTPS or SSH repository URL." }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $invalid }
    $trimmed = $Value.Trim()

    if ($AllowLocal) {
        try {
            if (Test-Path -LiteralPath $trimmed -PathType Container) {
                $local = [System.IO.Path]::GetFullPath($trimmed)
                return [pscustomobject]@{ valid = $true; type = "local-test"; gitUrl = $local; webUrl = ""; display = $local; owner = ""; repository = ""; message = "" }
            }
        }
        catch { }
    }

    $owner = ""
    $repository = ""

    if ($trimmed -match '^git@github\.com:([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $repository = $Matches[2] -replace '\.git$', ''
    }
    else {
        $uri = $null
        if (-not [Uri]::TryCreate($trimmed, [UriKind]::Absolute, [ref]$uri)) { return $invalid }
        if ($uri.Scheme -ne "https" -or $uri.Host -ne "github.com" -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
            return $invalid
        }
        $segments = @($uri.AbsolutePath.Trim('/') -split '/')
        if ($segments.Count -ne 2) { return $invalid }
        $owner = $segments[0]
        $repository = $segments[1] -replace '\.git$', ''
    }

    if (-not (Test-GitHubName -Owner $owner -Repository $repository)) { return $invalid }
    $webUrl = "https://github.com/$owner/$repository"
    return [pscustomobject]@{
        valid = $true
        type = "github"
        gitUrl = "$webUrl.git"
        webUrl = $webUrl
        display = $webUrl
        owner = $owner
        repository = $repository
        message = ""
    }
}

function Redact-RemoteValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    try {
        $uri = New-Object Uri($Value)
        if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
            $builder = New-Object UriBuilder($uri)
            $builder.UserName = ""
            $builder.Password = ""
            return $builder.Uri.AbsoluteUri
        }
    }
    catch { }
    return ($Value -replace '://[^/@\s]+@', '://[credentials-redacted]@')
}

function Get-OriginInfo {
    param([string]$RepoPath)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("remote", "get-url", "origin") -DisplayCommand "read origin" -TimeoutSeconds 10 -ReadOnly
    if (-not $result.ok -or [string]::IsNullOrWhiteSpace($result.raw)) {
        return [pscustomobject]@{ configured = $false; valid = $false; type = "none"; gitUrl = ""; display = ""; webUrl = ""; owner = ""; repository = "" }
    }

    $raw = $result.raw.Trim()
    $parsed = ConvertTo-GitHubRemoteValue -Value $raw -AllowLocal:$script:AppState.AllowLocalTestRemote
    if ($parsed.valid) {
        return [pscustomobject]@{ configured = $true; valid = $true; type = $parsed.type; gitUrl = $parsed.gitUrl; display = $parsed.display; webUrl = $parsed.webUrl; owner = $parsed.owner; repository = $parsed.repository }
    }

    return [pscustomobject]@{ configured = $true; valid = $false; type = "unsupported"; gitUrl = ""; display = (Redact-RemoteValue $raw); webUrl = ""; owner = ""; repository = "" }
}

function Get-NulItems {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    $parts = $Text.Split([char]0)
    $items = New-Object 'System.Collections.Generic.List[string]'
    foreach ($part in $parts) {
        if ($part.Length -gt 0) { $items.Add($part) }
    }
    return $items.ToArray()
}

function Get-FileState {
    param([string]$Status, [bool]$Tracked)
    if (-not $Tracked -or $Status -eq "??") { return "untracked" }
    if ($Status -match 'U|AA|DD') { return "conflicted" }
    $indexChanged = ($Status.Length -gt 0 -and $Status[0] -notin @(' ', '.'))
    $worktreeChanged = ($Status.Length -gt 1 -and $Status[1] -notin @(' ', '.'))
    if ($indexChanged -and $worktreeChanged) { return "mixed" }
    if ($indexChanged) { return "staged" }
    if ($worktreeChanged -and $Status[1] -eq 'D') { return "deleted" }
    if ($worktreeChanged) { return "modified" }
    return "unchanged"
}

function Get-WorkingTreeState {
    param([string]$RepoPath, [switch]$Force)
    $cacheKey = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')
    if (-not $Force) {
        $cached = Get-BranchlineCacheEntry -Name "local-status" -Key $cacheKey -MaximumAgeMilliseconds 2000
        if ($null -ne $cached) { return $cached }
    }

    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all") -DisplayCommand "read repository state" -TimeoutSeconds 30 -ReadOnly
    $scannedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $duration = if ($null -ne $result.PSObject.Properties["durationSeconds"]) { [double]$result.durationSeconds } else { 0.0 }
    $durationMilliseconds = if ($null -ne $result.PSObject.Properties["durationMilliseconds"]) { [double]$result.durationMilliseconds } else { [Math]::Round($duration * 1000, 1) }
    $script:AppState.LocalScannedAt = $scannedAt
    if (-not $result.ok) {
        Remove-BranchlineCacheEntry -Name "local-status"
        return [pscustomobject][ordered]@{
            ok = $false
            files = @()
            error = if ([string]::IsNullOrWhiteSpace($result.output)) { "Git could not read the working tree." } else { $result.output }
            signature = ""
            scannedAt = $scannedAt
            durationSeconds = $duration
            durationMilliseconds = $durationMilliseconds
            branch = ""
            headState = "error"
            headCommit = ""
            upstream = ""
            ahead = 0
            behind = 0
        }
    }

    $items = @(Get-NulItems $result.raw)
    $files = New-Object System.Collections.Generic.List[object]
    $branch = ""
    $headCommit = ""
    $upstream = ""
    $ahead = 0
    $behind = 0
    $sawBranchHead = $false
    $sawBranchOid = $false
    for ($index = 0; $index -lt $items.Count; $index += 1) {
        $record = [string]$items[$index]
        if ($record.StartsWith("# branch.oid ")) {
            $headCommit = $record.Substring(13).Trim()
            $sawBranchOid = $true
            continue
        }
        if ($record.StartsWith("# branch.head ")) {
            $branch = $record.Substring(14).Trim()
            $sawBranchHead = $true
            continue
        }
        if ($record.StartsWith("# branch.upstream ")) {
            $upstream = $record.Substring(18).Trim()
            continue
        }
        if ($record -match '^# branch\.ab \+(\d+) -(\d+)$') {
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
            continue
        }

        $status = ""
        $path = ""
        $originalPath = ""
        $tracked = $true
        if ($record.StartsWith("1 ")) {
            $parts = $record.Split(@(' '), 9, [System.StringSplitOptions]::None)
            if ($parts.Count -lt 9) { continue }
            $status = $parts[1].Replace('.', ' ')
            $path = $parts[8].Replace('\', '/')
        }
        elseif ($record.StartsWith("2 ")) {
            $parts = $record.Split(@(' '), 10, [System.StringSplitOptions]::None)
            if ($parts.Count -lt 10) { continue }
            $status = $parts[1].Replace('.', ' ')
            $path = $parts[9].Replace('\', '/')
            if ($index + 1 -lt $items.Count) {
                $index += 1
                $originalPath = ([string]$items[$index]).Replace('\', '/')
            }
        }
        elseif ($record.StartsWith("u ")) {
            $parts = $record.Split(@(' '), 11, [System.StringSplitOptions]::None)
            if ($parts.Count -lt 11) { continue }
            $status = $parts[1].Replace('.', ' ')
            $path = $parts[10].Replace('\', '/')
        }
        elseif ($record.StartsWith("? ")) {
            $status = "??"
            $path = $record.Substring(2).Replace('\', '/')
            $tracked = $false
        }
        else { continue }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (($status.Contains("R") -or $status.Contains("C")) -and [string]::IsNullOrWhiteSpace($originalPath) -and $index + 1 -lt $items.Count) {
            $index += 1
            $originalPath = ([string]$items[$index]).Replace('\', '/')
        }
        $files.Add([pscustomobject]@{
            status = $status
            path = $path
            originalPath = $originalPath
            tracked = $tracked
            state = Get-FileState -Status $status -Tracked $tracked
        })
    }
    if (-not $sawBranchHead -or -not $sawBranchOid) {
        Remove-BranchlineCacheEntry -Name "local-status"
        return [pscustomobject][ordered]@{
            ok = $false; files = @(); error = "Git returned repository status without complete branch metadata."; signature = ""; scannedAt = $scannedAt
            durationSeconds = $duration; durationMilliseconds = $durationMilliseconds; branch = ""; headState = "error"; headCommit = ""; upstream = ""; ahead = 0; behind = 0
        }
    }
    $headState = if ($branch -eq "(detached)") { "detached" } elseif ($headCommit -eq "(initial)") { "unborn" } else { "branch" }
    if ($headState -eq "detached") { $branch = "" }
    if ($headState -eq "unborn") { $headCommit = "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$result.raw)
        $signature = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
    $script:AppState.LocalStatusSignature = $signature
    $state = [pscustomobject][ordered]@{
        ok = $true
        files = @($files | ForEach-Object { $_ })
        error = ""
        signature = $signature
        scannedAt = $scannedAt
        durationSeconds = $duration
        durationMilliseconds = $durationMilliseconds
        branch = $branch
        headState = $headState
        headCommit = $headCommit
        upstream = $upstream
        ahead = $ahead
        behind = $behind
    }
    Set-BranchlineCacheEntry -Name "local-status" -Key $cacheKey -Value $state -SizeBytes ([Math]::Max(4096, $result.raw.Length * 2)) | Out-Null
    return $state
}

function Get-ChangedFiles {
    param([string]$RepoPath, [switch]$Force)
    $state = Get-WorkingTreeState $RepoPath -Force:$Force
    if (-not $state.ok) { throw "Branchline could not verify the working tree. No changing action was attempted.`n$($state.error)" }
    return @($state.files)
}

function Get-RepositoryFiles {
    param([string]$RepoPath, [object[]]$ChangedFiles)

    $allResult = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-files", "--cached", "--others", "--exclude-standard", "-z") -DisplayCommand "read repository files" -TimeoutSeconds 30 -ReadOnly
    if (-not $allResult.ok) { throw "Branchline could not list repository files.`n$($allResult.output)" }
    $allPaths = @(Get-NulItems $allResult.raw)

    $trackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $allSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $untrackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $ChangedFiles) {
        if (-not [bool]$file.tracked) { [void]$untrackedSet.Add([string]$file.path) }
    }
    foreach ($item in $allPaths) {
        $path = ([string]$item).Replace('\', '/')
        [void]$allSet.Add($path)
        if (-not $untrackedSet.Contains($path)) { [void]$trackedSet.Add($path) }
    }
    foreach ($file in $ChangedFiles) { [void]$allSet.Add([string]$file.path) }

    $statusMap = @{}
    foreach ($file in $ChangedFiles) { $statusMap[[string]$file.path] = $file }

    $orderedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($file in @($ChangedFiles | Sort-Object path)) {
        if (-not $orderedPaths.Contains([string]$file.path)) { $orderedPaths.Add([string]$file.path) }
    }
    foreach ($path in @($allSet | Sort-Object)) {
        if (-not $orderedPaths.Contains([string]$path)) { $orderedPaths.Add([string]$path) }
    }

    $limit = 500
    $visible = @($orderedPaths | Select-Object -First $limit | ForEach-Object {
        $path = [string]$_
        $trackedFile = $trackedSet.Contains($path)
        $changed = if ($statusMap.ContainsKey($path)) { $statusMap[$path] } else { $null }
        $status = if ($null -ne $changed) { [string]$changed.status } else { "" }
        [pscustomobject]@{
            path = $path
            tracked = $trackedFile
            status = $status
            state = if ($null -ne $changed) { [string]$changed.state } else { Get-FileState -Status "" -Tracked $trackedFile }
        }
    })

    return [pscustomobject]@{ files = $visible; total = $allSet.Count; truncated = ($allSet.Count -gt $limit) }
}

function Resolve-RepositoryFile {
    param([string]$RepoPath, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)) {
        throw "Choose a repository file first."
    }
    $normalized = $Path.Replace('\', '/').TrimStart('/')
    if ($normalized -eq ".git" -or $normalized.StartsWith(".git/") -or $normalized -match '(^|/)\.\.(/|$)' -or $normalized.Contains(":")) {
        throw "That file path is not allowed."
    }

    $changedMatch = @(Get-ChangedFiles $RepoPath | Where-Object { ([string]$_.path) -ceq $normalized })
    if ($changedMatch.Count -eq 1) { return $normalized }

    $tracked = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--literal-pathspecs", "ls-files", "--error-unmatch", "--", $normalized) -DisplayCommand "validate file" -TimeoutSeconds 10 -ReadOnly
    if ($tracked.ok) { return $normalized }

    $untracked = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "--literal-pathspecs", "ls-files", "--others", "--exclude-standard", "-z", "--", $normalized) -DisplayCommand "validate file" -TimeoutSeconds 10 -ReadOnly
    $matches = if ($untracked.ok) { @(Get-NulItems $untracked.raw) } else { @() }
    if (@($matches | Where-Object { ([string]$_).Replace('\', '/') -ceq $normalized }).Count -eq 1) { return $normalized }
    throw "The selected file is not part of the active repository."
}

function Test-TrackedFile {
    param([string]$RepoPath, [string]$Path)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--literal-pathspecs", "ls-files", "--error-unmatch", "--", $Path) -DisplayCommand "check tracked file" -TimeoutSeconds 10 -ReadOnly
    return $result.ok
}

function Get-CurrentBranch {
    param([string]$RepoPath)
    $state = Get-WorkingTreeState $RepoPath
    if ($state.ok -and $state.headState -ne "detached") { return [string]$state.branch }
    return ""
}

function Get-HeadState {
    param([string]$RepoPath)
    $state = Get-WorkingTreeState $RepoPath
    if (-not $state.ok) { throw "Branchline could not determine whether HEAD is attached, detached, or unborn.`n$($state.error)" }
    return [pscustomobject]@{ state = [string]$state.headState; branch = [string]$state.branch; commit = [string]$state.headCommit }
}

function Test-BranchName {
    param([string]$RepoPath, [string]$Branch)
    if ([string]::IsNullOrWhiteSpace($Branch) -or $Branch.StartsWith("-")) { return $false }
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("check-ref-format", "--branch", $Branch) -DisplayCommand "validate branch" -TimeoutSeconds 10
    return $result.ok
}

function Get-Branches {
    param([string]$RepoPath)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("for-each-ref", "--format=%(refname:short)%09%(HEAD)%09%(upstream:short)", "refs/heads") -DisplayCommand "read branches" -TimeoutSeconds 15 -ReadOnly
    if (-not $result.ok) { throw "Branchline could not read local branches.`n$($result.output)" }
    return @($result.raw -split '(?:\r\n|\n|\r)' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $parts = $_ -split "`t", 3
        if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
            [pscustomobject]@{ name = $parts[0]; current = ($parts[1] -eq "*"); upstream = if ($parts.Count -ge 3) { $parts[2] } else { "" } }
        }
    })
}

function Get-RemoteReferenceInfo {
    param([string]$RepoPath)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("for-each-ref", "--format=%(refname:strip=3)%09%(symref)", "refs/remotes/origin") -DisplayCommand "read remote branches" -TimeoutSeconds 15 -ReadOnly
    if (-not $result.ok) { throw "Branchline could not read the fetched GitHub branches.`n$($result.output)" }
    $branches = New-Object System.Collections.Generic.List[string]
    $defaultBranch = ""
    foreach ($line in @($result.raw -split '(?:\r\n|\n|\r)' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $parts = $line -split "`t", 2
        $name = $parts[0].Trim()
        if ($name -eq "HEAD") {
            if ($parts.Count -ge 2 -and $parts[1].Trim() -match '^refs/remotes/origin/(.+)$') { $defaultBranch = $Matches[1] }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($name)) { $branches.Add($name) }
    }
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        if ($branches.Contains("main")) { $defaultBranch = "main" }
        elseif ($branches.Contains("master")) { $defaultBranch = "master" }
        elseif ($branches.Count -gt 0) { $defaultBranch = $branches[0] }
    }
    return [pscustomobject]@{ branches = @($branches); defaultBranch = $defaultBranch }
}

function Get-RemoteDefaultBranch {
    param([string]$RepoPath)
    return [string](Get-RemoteReferenceInfo $RepoPath).defaultBranch
}

function Get-RemoteBranches {
    param([string]$RepoPath)
    return @((Get-RemoteReferenceInfo $RepoPath).branches)
}

function Test-GitRef {
    param([string]$RepoPath, [string]$Ref)
    if ([string]::IsNullOrWhiteSpace($Ref)) { return $false }
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("show-ref", "--verify", "--quiet", $Ref) -DisplayCommand "check Git reference" -TimeoutSeconds 10 -ReadOnly
    return $result.ok
}

function Test-RefsRelated {
    param([string]$RepoPath, [string]$Left, [string]$Right)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("merge-base", $Left, $Right) -DisplayCommand "compare repository histories" -TimeoutSeconds 15 -ReadOnly
    return $result.ok
}

function Get-RecentCommits {
    param([string]$RepoPath)
    $format = "%H%x1f%h%x1f%s%x1f%cr%x1e"
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--no-pager", "log", "-80", "--format=$format") -DisplayCommand "read history" -TimeoutSeconds 20 -ReadOnly
    if (-not $result.ok) { return @() }
    return @($result.raw.Split([char]0x1e) | ForEach-Object {
        $record = $_.Trim("`r", "`n")
        if (-not [string]::IsNullOrWhiteSpace($record)) {
            $parts = $record.Split([char]0x1f)
            if ($parts.Count -ge 4) {
                [pscustomobject]@{ hash = $parts[0]; shortHash = $parts[1]; subject = $parts[2]; time = $parts[3] }
            }
        }
    })
}

function Resolve-Commit {
    param([string]$RepoPath, [string]$Commit)
    if ($Commit -notmatch '^[A-Fa-f0-9]{40,64}$') { throw "Choose a full commit identifier from the history list." }
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-parse", "--verify", "$Commit^{commit}") -DisplayCommand "validate commit" -TimeoutSeconds 10
    if (-not $result.ok) { throw "The selected commit no longer exists." }
    return $result.raw.Trim()
}

function Get-TrackingStatus {
    param([string]$RepoPath, [string]$Branch, [object[]]$LocalBranches = @())
    $status = [ordered]@{
        hasUpstream = $false; upstream = ""; upstreamExists = $false; mismatch = $false
        matchingRemoteExists = $false; remoteBranch = $Branch; remoteDefaultBranch = ""; remoteHasBranches = $false; remoteBranchNames = @()
        hasLocalCommit = $false; ahead = 0; behind = 0; diverged = $false; relationship = "no-remote"; error = ""
    }
    if ([string]::IsNullOrWhiteSpace($Branch)) {
        $status.relationship = "local-empty"
        return [pscustomobject]$status
    }
    if ($LocalBranches.Count -eq 0) { $LocalBranches = @(Get-Branches $RepoPath) }
    $currentLocalBranch = @($LocalBranches | Where-Object { [string]$_.name -ceq $Branch } | Select-Object -First 1)
    $status.hasLocalCommit = ($currentLocalBranch.Count -eq 1)
    $remoteInfo = Get-RemoteReferenceInfo $RepoPath
    $status.remoteDefaultBranch = [string]$remoteInfo.defaultBranch
    $remoteBranches = @($remoteInfo.branches)
    $status.remoteBranchNames = $remoteBranches
    $status.remoteHasBranches = ($remoteBranches.Count -gt 0)
    $matchingRef = "refs/remotes/origin/$Branch"
    $status.matchingRemoteExists = ($remoteBranches -ccontains $Branch)

    $upstream = if ($currentLocalBranch.Count -eq 1) { [string]$currentLocalBranch[0].upstream } else { "" }
    $status.upstream = $upstream
    $status.hasUpstream = -not [string]::IsNullOrWhiteSpace($upstream)
    if ($status.hasUpstream) {
        $status.upstreamExists = ($upstream.StartsWith("origin/") -and ($remoteBranches -ccontains $upstream.Substring(7)))
    }
    if ($status.hasUpstream -and $upstream -ne "origin/$Branch") {
        $status.mismatch = $true
        $status.relationship = "upstream-mismatch"
        return [pscustomobject]$status
    }

    if (-not $status.hasLocalCommit) {
        $status.relationship = if ($status.remoteHasBranches) { "local-empty" } else { "both-empty" }
        return [pscustomobject]$status
    }

    if ($status.matchingRemoteExists) {
        if (-not (Test-RefsRelated -RepoPath $RepoPath -Left "HEAD" -Right $matchingRef)) {
            $status.relationship = "unrelated"
            return [pscustomobject]$status
        }
        $counts = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-list", "--left-right", "--count", "$matchingRef...HEAD") -DisplayCommand "read sync state" -TimeoutSeconds 15 -ReadOnly
        if (-not $counts.ok -or $counts.raw.Trim() -notmatch '^(\d+)\s+(\d+)$') {
            $status.relationship = "error"
            $status.error = if ([string]::IsNullOrWhiteSpace($counts.output)) { "Git could not compare the local and GitHub branches." } else { $counts.output }
            return [pscustomobject]$status
        }
        $status.behind = [int]$Matches[1]
        $status.ahead = [int]$Matches[2]
        $status.diverged = ($status.behind -gt 0 -and $status.ahead -gt 0)
        $status.relationship = if ($status.diverged) { "diverged" } elseif ($status.behind -gt 0) { "behind" } elseif ($status.ahead -gt 0) { "ahead" } else { "in-sync" }
        return [pscustomobject]$status
    }

    if (-not $status.remoteHasBranches) {
        $status.relationship = "remote-empty"
        return [pscustomobject]$status
    }

    $defaultRef = if ([string]::IsNullOrWhiteSpace($status.remoteDefaultBranch)) { "" } else { "refs/remotes/origin/$($status.remoteDefaultBranch)" }
    if (-not [string]::IsNullOrWhiteSpace($defaultRef) -and ($remoteBranches -ccontains $status.remoteDefaultBranch)) {
        $status.relationship = if (Test-RefsRelated -RepoPath $RepoPath -Left "HEAD" -Right $defaultRef) { "unpublished" } else { "unrelated" }
        return [pscustomobject]$status
    }

    $status.relationship = "remote-branch-missing"
    return [pscustomobject]$status
}

function Get-RangeCommits {
    param([string]$RepoPath, [string]$Range)
    if ([string]::IsNullOrWhiteSpace($Range)) { return @() }
    $format = "%H%x1f%h%x1f%s%x1f%cr%x1e"
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--no-pager", "log", "-40", "--format=$format", $Range) -DisplayCommand "read comparison history" -TimeoutSeconds 20 -ReadOnly
    if (-not $result.ok) { return @() }
    return @($result.raw.Split([char]0x1e) | ForEach-Object {
        $record = $_.Trim("`r", "`n")
        if (-not [string]::IsNullOrWhiteSpace($record)) {
            $parts = $record.Split([char]0x1f)
            if ($parts.Count -ge 4) { [pscustomobject]@{ hash = $parts[0]; shortHash = $parts[1]; subject = $parts[2]; time = $parts[3] } }
        }
    })
}

function Get-RemoteSnapshot {
    param([string]$RepoPath, [object]$Tracking, [string]$HeadCommit = "")
    $remoteBranch = if ($Tracking.matchingRemoteExists) { [string]$Tracking.remoteBranch } else { [string]$Tracking.remoteDefaultBranch }
    if ([string]::IsNullOrWhiteSpace($remoteBranch)) {
        return [pscustomobject]@{ available = $false; branch = ""; files = @(); fileCount = 0; truncated = $false; incomingFiles = @(); incomingCommits = @(); outgoingCommits = @() }
    }
    $remoteRef = "refs/remotes/origin/$remoteBranch"
    if ([string]$Tracking.relationship -eq "remote-branch-missing") {
        return [pscustomobject]@{ available = $false; branch = $remoteBranch; files = @(); fileCount = 0; truncated = $false; incomingFiles = @(); incomingCommits = @(); outgoingCommits = @() }
    }

    $remoteObject = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-parse", "--verify", $remoteRef) -DisplayCommand "identify fetched GitHub snapshot" -TimeoutSeconds 10 -ReadOnly
    if (-not $remoteObject.ok) { throw "Branchline could not verify the fetched GitHub branch.`n$($remoteObject.output)" }
    $localObjectId = if ([string]::IsNullOrWhiteSpace($HeadCommit)) { "unborn" } else { $HeadCommit }
    $snapshotKey = "$RepoPath|$remoteBranch|$($remoteObject.raw.Trim())|$localObjectId|$($Tracking.relationship)"
    if ($script:AppState.RemoteSnapshotKey -ceq $snapshotKey -and $null -ne $script:AppState.RemoteSnapshotCache) {
        return $script:AppState.RemoteSnapshotCache
    }

    $incomingPaths = @()
    $incomingCommits = @()
    $outgoingCommits = @()
    if ([string]$Tracking.relationship -in @("behind", "diverged")) {
        $incoming = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "diff", "--name-only", "-z", "HEAD..$remoteRef") -DisplayCommand "read incoming files" -TimeoutSeconds 30 -ReadOnly
        if ($incoming.ok) { $incomingPaths = @(Get-NulItems $incoming.raw) }
        $incomingCommits = @(Get-RangeCommits -RepoPath $RepoPath -Range "HEAD..$remoteRef")
    }
    if ([string]$Tracking.relationship -in @("ahead", "diverged")) {
        $outgoingCommits = @(Get-RangeCommits -RepoPath $RepoPath -Range "$remoteRef..HEAD")
    }
    $files = @($incomingPaths | Select-Object -First 500 | ForEach-Object { [pscustomobject]@{ path = ([string]$_).Replace('\', '/'); state = "incoming" } })
    $snapshot = [pscustomobject]@{
        available = $true; branch = $remoteBranch; files = $files; fileCount = $files.Count; truncated = ($incomingPaths.Count -gt 500)
        incomingFiles = @($incomingPaths | ForEach-Object { ([string]$_).Replace('\', '/') })
        incomingCommits = $incomingCommits; outgoingCommits = $outgoingCommits
    }
    $script:AppState.RemoteSnapshotKey = $snapshotKey
    $script:AppState.RemoteSnapshotCache = $snapshot
    return $snapshot
}

function Get-GitIdentity {
    param([string]$RepoPath)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("config", "--local", "--get-regexp", "^user\.(name|email)$") -DisplayCommand "read repository commit identity" -TimeoutSeconds 10 -ReadOnly
    $name = ""
    $email = ""
    if ($result.ok) {
        foreach ($line in @($result.raw -split '(?:\r\n|\n|\r)')) {
            if ($line -match '^user\.name\s+(.*)$') { $name = $Matches[1].Trim() }
            elseif ($line -match '^user\.email\s+(.*)$') { $email = $Matches[1].Trim() }
        }
    }
    $configured = (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($email))
    $inheritedName = $name
    $inheritedEmail = $email
    if (-not $configured) {
        $effectiveResult = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("config", "--get-regexp", "^user\.(name|email)$") -DisplayCommand "read effective commit identity" -TimeoutSeconds 10 -ReadOnly
        $inheritedName = ""
        $inheritedEmail = ""
        if ($effectiveResult.ok) {
            foreach ($line in @($effectiveResult.raw -split '(?:\r\n|\n|\r)')) {
                if ($line -match '^user\.name\s+(.*)$') { $inheritedName = $Matches[1].Trim() }
                elseif ($line -match '^user\.email\s+(.*)$') { $inheritedEmail = $Matches[1].Trim() }
            }
        }
    }
    return [pscustomobject]@{
        configured = $configured
        name = $name
        email = $email
        inheritedAvailable = (-not $configured -and -not [string]::IsNullOrWhiteSpace($inheritedName) -and -not [string]::IsNullOrWhiteSpace($inheritedEmail))
        inheritedName = $inheritedName
        inheritedEmail = $inheritedEmail
        source = if ($configured) { "repository" } elseif (-not [string]::IsNullOrWhiteSpace($inheritedName) -and -not [string]::IsNullOrWhiteSpace($inheritedEmail)) { "global" } else { "missing" }
    }
}

function Assert-GitIdentity {
    param([string]$RepoPath)
    $identity = Get-GitIdentity $RepoPath
    if (-not $identity.configured) {
        throw "Set the commit author name and email in Branchline before creating a commit. They are saved only for this repository."
    }
    return $identity
}

function Assert-CommitDoesNotForkRemoteHistory {
    param([string]$RepoPath)
    $origin = Get-OriginInfo $RepoPath
    if (-not $origin.valid) { return }
    $branch = Get-CurrentBranch $RepoPath
    $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch $branch
    if ([string]$tracking.relationship -eq "local-empty") {
        throw "GitHub already has history. Use Bring GitHub here before committing so this work continues the GitHub project instead of creating an unrelated history."
    }
}

function Test-SafeIdentityName {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Length -le 100 -and $Value -notmatch '[<>\r\n]')
}

function Test-SafeIdentityEmail {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Length -le 254 -and $Value -match '^[A-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+$')
}

function Test-SafeRepositoryRelativePath {
    param([string]$RepoPath, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path) -or $Path -match '(^|/|\\)\.\.($|/|\\)') { return $false }
    $root = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $RepoPath $Path.Replace('/', '\')))
    return $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-AdoptRemoteHistory {
    param([string]$RepoPath, [string]$Confirmation)
    [void](Assert-OriginAllowed $RepoPath)
    $workingState = Get-WorkingTreeState $RepoPath -Force
    if (-not $workingState.ok) { throw "Branchline could not inspect local files, so GitHub history was not adopted.`n$($workingState.error)" }
    $operation = Get-GitOperationState $RepoPath
    if (-not [string]::IsNullOrWhiteSpace($operation)) { throw "Finish or abort the active $operation before bringing GitHub history here." }
    $currentBranch = Get-CurrentBranch $RepoPath
    if ([string]::IsNullOrWhiteSpace($currentBranch)) { throw "Branchline could not determine the local branch name." }

    $fetch = Invoke-OriginFetch -RepoPath $RepoPath -DisplayCommand "check GitHub before bringing it here"
    if (-not $fetch.ok) { return $fetch }
    $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch $currentBranch
    if ([string]$tracking.relationship -ne "local-empty") {
        throw "Bring GitHub here is available only when the local repository has no commits and GitHub already has a default branch."
    }

    $remoteBranch = [string]$tracking.remoteDefaultBranch
    if ([string]::IsNullOrWhiteSpace($remoteBranch)) { throw "GitHub's default branch could not be determined." }
    if ($Confirmation -cne "ADOPT_GITHUB:$remoteBranch") { throw "Bring-GitHub-here confirmation was missing." }
    $remoteRef = "refs/remotes/origin/$remoteBranch"
    if ($currentBranch -cne $remoteBranch -and (Test-GitRef -RepoPath $RepoPath -Ref "refs/heads/$remoteBranch")) {
        throw "A local branch named '$remoteBranch' already exists. Choose it explicitly instead of replacing it."
    }

    $tree = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-tree", "-r", "--name-only", "-z", $remoteRef) -DisplayCommand "inspect GitHub files before bringing them here" -TimeoutSeconds 30
    if (-not $tree.ok) { return $tree }
    $missing = New-Object System.Collections.Generic.List[string]
    $structuralConflicts = New-Object System.Collections.Generic.List[string]
    foreach ($remotePathValue in @(Get-NulItems $tree.raw)) {
        $remotePath = ([string]$remotePathValue).Replace('\', '/')
        if (-not (Test-SafeRepositoryRelativePath -RepoPath $RepoPath -Path $remotePath)) { throw "GitHub contains a path that Branchline cannot handle safely." }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoPath $remotePath.Replace('/', '\')))
        if (Test-Path -LiteralPath $fullPath) {
            if (Test-Path -LiteralPath $fullPath -PathType Container) { $structuralConflicts.Add($remotePath) }
            continue
        }
        $parent = Split-Path -Parent $fullPath
        $blockedParent = $false
        while (-not [string]::IsNullOrWhiteSpace($parent) -and -not $parent.Equals($RepoPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            if (Test-Path -LiteralPath $parent -PathType Leaf) { $blockedParent = $true; break }
            $nextParent = Split-Path -Parent $parent
            if ($nextParent -eq $parent) { break }
            $parent = $nextParent
        }
        if ($blockedParent) { $structuralConflicts.Add($remotePath) } else { $missing.Add($remotePath) }
    }
    if ($structuralConflicts.Count -gt 0) {
        $preview = @($structuralConflicts | Select-Object -First 5) -join ", "
        throw "Local file/folder structure conflicts with GitHub at: $preview. Clone GitHub into an empty folder, then copy your local work into it."
    }

    $gitDirectory = Get-GitDirectoryPath $RepoPath
    $transactionId = New-RecoveryId
    $transactionDirectory = Join-Path $gitDirectory "branchline\transactions\adopt-$transactionId"
    [System.IO.Directory]::CreateDirectory($transactionDirectory) | Out-Null
    $headPath = Join-Path $gitDirectory "HEAD"
    $indexPath = Join-Path $gitDirectory "index"
    $configPath = Join-Path $gitDirectory "config"
    $originalHead = [System.IO.File]::ReadAllText($headPath)
    $hadIndex = Test-Path -LiteralPath $indexPath -PathType Leaf
    if ($hadIndex) { Copy-Item -LiteralPath $indexPath -Destination (Join-Path $transactionDirectory "index") -Force }
    if (Test-Path -LiteralPath $configPath -PathType Leaf) { Copy-Item -LiteralPath $configPath -Destination (Join-Path $transactionDirectory "config") -Force }
    [System.IO.File]::WriteAllText((Join-Path $transactionDirectory "HEAD"), $originalHead, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $transactionDirectory "manifest.json"), ([ordered]@{
        operation = "adoptRemote"
        createdAt = (Get-Date).ToString("o")
        originalBranch = $currentBranch
        remoteBranch = $remoteBranch
        filesAdded = @($missing)
    } | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

    $outputs = New-Object System.Collections.Generic.List[string]
    $outputs.Add($fetch.output)
    $mutated = $false
    try {
        $reset = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("reset", "--mixed", $remoteRef) -DisplayCommand "adopt GitHub history without overwriting local files" -TimeoutSeconds 60
        if (-not $reset.ok) { throw $reset.output }
        $mutated = $true
        $outputs.Add($reset.output)

        for ($offset = 0; $offset -lt $missing.Count; $offset += 80) {
            $count = [Math]::Min(80, $missing.Count - $offset)
            $batch = @($missing.GetRange($offset, $count))
            $arguments = @("--literal-pathspecs", "restore", "--source=$remoteRef", "--worktree", "--") + $batch
            $restore = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments $arguments -DisplayCommand "bring missing GitHub files into the folder" -TimeoutSeconds 60
            if (-not $restore.ok) { throw $restore.output }
            if (-not [string]::IsNullOrWhiteSpace($restore.output)) { $outputs.Add($restore.output) }
        }

        $activeBranch = $currentBranch
        if ($currentBranch -cne $remoteBranch) {
            $rename = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("branch", "-m", $remoteBranch) -DisplayCommand "rename local branch to $remoteBranch" -TimeoutSeconds 30
            if (-not $rename.ok) { throw $rename.output }
            $outputs.Add($rename.output)
            $activeBranch = $remoteBranch
        }
        $upstream = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("branch", "--set-upstream-to=origin/$remoteBranch", $activeBranch) -DisplayCommand "track origin/$remoteBranch" -TimeoutSeconds 30
        if (-not $upstream.ok) { throw $upstream.output }
        $outputs.Add($upstream.output)
        Remove-Item -LiteralPath $transactionDirectory -Recurse -Force -ErrorAction SilentlyContinue
        return New-AppResult -Ok $true -Command "bring GitHub here" -Output (Join-CommandOutput @(
            @($outputs),
            "GitHub history is now the base of this folder. Existing local files were preserved, missing GitHub files were added, and staging was cleared for review."
        )) -Phase "complete" -Steps @(
            (New-ActionStep "Fetch GitHub" "completed" "git fetch origin" $fetch.output),
            (New-ActionStep "Adopt history" "completed" "git reset --mixed" $reset.output),
            (New-ActionStep "Restore missing files" "completed" "git restore" "$($missing.Count) file(s) added"),
            (New-ActionStep "Set tracking" "completed" "git branch --set-upstream-to" $upstream.output)
        )
    }
    catch {
        $failure = $_.Exception.Message
        $rollbackErrors = New-Object System.Collections.Generic.List[string]
        if ($mutated) {
            foreach ($remotePathValue in @($missing)) {
                try {
                    $candidate = [System.IO.Path]::GetFullPath((Join-Path $RepoPath ([string]$remotePathValue).Replace('/', '\')))
                    if ($candidate.StartsWith($RepoPath.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                        Remove-Item -LiteralPath $candidate -Force -ErrorAction Stop
                    }
                }
                catch { $rollbackErrors.Add($_.Exception.Message) }
            }
            try {
                $currentAfterFailure = Get-CurrentBranch $RepoPath
                if (-not [string]::IsNullOrWhiteSpace($currentAfterFailure)) {
                    [void](Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("update-ref", "-d", "refs/heads/$currentAfterFailure") -DisplayCommand "remove partial adopted branch" -TimeoutSeconds 15)
                }
                [System.IO.File]::WriteAllText($headPath, $originalHead, (New-Object System.Text.UTF8Encoding($false)))
            }
            catch { $rollbackErrors.Add($_.Exception.Message) }
            try {
                if ($hadIndex) { Copy-Item -LiteralPath (Join-Path $transactionDirectory "index") -Destination $indexPath -Force }
                elseif (Test-Path -LiteralPath $indexPath -PathType Leaf) { Remove-Item -LiteralPath $indexPath -Force }
            }
            catch { $rollbackErrors.Add($_.Exception.Message) }
            try {
                $savedConfig = Join-Path $transactionDirectory "config"
                if (Test-Path -LiteralPath $savedConfig -PathType Leaf) { Copy-Item -LiteralPath $savedConfig -Destination $configPath -Force }
            }
            catch { $rollbackErrors.Add($_.Exception.Message) }
        }
        $rolledBack = ($rollbackErrors.Count -eq 0)
        if ($rolledBack) { Remove-Item -LiteralPath $transactionDirectory -Recurse -Force -ErrorAction SilentlyContinue }
        $rollbackMessage = if ($rolledBack) { "The partial adoption was rolled back; existing local files remain in place." } else { "Rollback needs attention. Recovery journal: $transactionDirectory`n$($rollbackErrors -join "`n")" }
        return New-AppResult -Ok $false -Code 1 -Command "bring GitHub here" -Output (Join-CommandOutput @($failure, $rollbackMessage)) -Partial (-not $rolledBack) -Phase "adopt" -Recovery @{ rolledBack = $rolledBack; journal = if ($rolledBack) { "" } else { $transactionDirectory } }
    }
}

function Test-CleanWorkingTree {
    param([string]$RepoPath, [switch]$Force)
    $state = Get-WorkingTreeState $RepoPath -Force:$Force
    if (-not $state.ok) {
        throw "Branchline could not verify whether the working tree is clean. The requested action was blocked.`n$($state.error)"
    }
    return (@($state.files).Count -eq 0)
}

function Test-GitStatePath {
    param([string]$RepoPath, [string]$StatePath)
    $result = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-parse", "--git-path", $StatePath) -DisplayCommand "read Git operation state" -TimeoutSeconds 10
    if (-not $result.ok -or [string]::IsNullOrWhiteSpace($result.raw)) { return $false }
    $path = $result.raw.Trim()
    if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $RepoPath $path }
    return (Test-Path -LiteralPath $path)
}

function Get-GitOperationState {
    param([string]$RepoPath)
    try { $gitDir = (Get-RepositoryMetadataPaths $RepoPath).gitDirectory }
    catch { return "" }
    if ([string]::IsNullOrWhiteSpace($gitDir)) { return "" }
    if (Test-Path -LiteralPath (Join-Path $gitDir "MERGE_HEAD")) { return "merge" }
    if (Test-Path -LiteralPath (Join-Path $gitDir "REVERT_HEAD")) { return "revert" }
    if (Test-Path -LiteralPath (Join-Path $gitDir "CHERRY_PICK_HEAD")) { return "cherry-pick" }
    if ((Test-Path -LiteralPath (Join-Path $gitDir "rebase-merge")) -or (Test-Path -LiteralPath (Join-Path $gitDir "rebase-apply"))) { return "rebase" }
    return ""
}

function Assert-RepositorySelected {
    if ([string]::IsNullOrWhiteSpace($script:AppState.RepoPath) -or -not (Test-Path -LiteralPath $script:AppState.RepoPath -PathType Container)) {
        throw "Choose a valid Git repository first."
    }
    return $script:AppState.RepoPath
}

function Assert-OriginAllowed {
    param([string]$RepoPath)
    $origin = Get-OriginInfo $RepoPath
    if (-not $origin.configured) { throw "Configure a GitHub origin first." }
    if (-not $origin.valid) { throw "The origin is not an approved GitHub URL." }
    return $origin
}

function Get-GitDirectoryPath {
    param([string]$RepoPath)
    return [string](Get-RepositoryMetadataPaths $RepoPath).gitDirectory
}

function Invoke-OriginFetch {
    param([string]$RepoPath, [string]$DisplayCommand = "git fetch origin")
    $fetch = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("fetch", "origin", "--prune") -DisplayCommand $DisplayCommand -TimeoutSeconds 120
    if (-not $fetch.ok) { return $fetch }
    $script:AppState.RemoteFetchedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $script:AppState.RemoteSnapshotCache = $null
    $script:AppState.RemoteSnapshotKey = ""
    # A remote may legitimately have no symbolic HEAD (for example an empty
    # repository), so refreshing it is best-effort and never changes Pull safety.
    [void](Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("remote", "set-head", "origin", "--auto") -DisplayCommand "refresh GitHub default branch" -TimeoutSeconds 30)
    return $fetch
}

function Save-RemoteConfigurationRecovery {
    param([string]$RepoPath)
    $gitDirectory = Get-GitDirectoryPath $RepoPath
    $recoveryDirectory = Join-Path $gitDirectory "branchline\remote-recovery"
    [System.IO.Directory]::CreateDirectory($recoveryDirectory) | Out-Null
    $origin = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("remote", "get-url", "origin") -DisplayCommand "read previous origin" -TimeoutSeconds 10
    $branches = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("for-each-ref", "--format=%(refname:short)%09%(upstream:short)", "refs/heads") -DisplayCommand "read previous upstreams" -TimeoutSeconds 15
    $record = [ordered]@{
        createdAt = (Get-Date).ToString("o")
        origin = if ($origin.ok) { $origin.raw.Trim() } else { "" }
        upstreams = if ($branches.ok) { @($branches.raw -split '(?:\r\n|\n|\r)' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() }
    }
    $path = Join-Path $recoveryDirectory ("remote-$(New-RecoveryId).json")
    [System.IO.File]::WriteAllText($path, ($record | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function New-SafetyReference {
    param([string]$RepoPath, [string]$Target = "HEAD")
    $reference = "refs/branchline/backups/$(New-RecoveryId)"
    $save = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("update-ref", $reference, $Target) -DisplayCommand "create Branchline safety reference" -TimeoutSeconds 15
    if (-not $save.ok) { return $save }
    return New-AppResult -Ok $true -Command "create Branchline safety reference" -Output "Safety reference created: $reference" -Data @{ backupRef = $reference }
}

function Invoke-PublishCurrentBranch {
    param([string]$RepoPath)
    [void](Assert-OriginAllowed $RepoPath)
    $branch = Get-CurrentBranch $RepoPath
    if (-not (Test-BranchName -RepoPath $RepoPath -Branch $branch)) { throw "The current branch cannot be published." }
    $head = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-parse", "--verify", "HEAD") -DisplayCommand "check local history" -TimeoutSeconds 10
    if (-not $head.ok) { throw "Create the first commit before publishing this branch." }
    $fetch = Invoke-OriginFetch -RepoPath $RepoPath -DisplayCommand "check GitHub before publishing"
    if (-not $fetch.ok) { return $fetch }
    $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch $branch
    if ($tracking.mismatch) { throw "This branch tracks '$($tracking.upstream)', not origin/$branch. Fix the upstream explicitly before publishing." }
    switch ([string]$tracking.relationship) {
        "unrelated" { throw "Publishing is blocked because the local project and GitHub repository have unrelated histories. Clone GitHub into an empty folder, or connect this local project to a different empty GitHub repository." }
        "behind" { throw "GitHub has incoming commits. Pull them safely before publishing." }
        "diverged" { throw "Local and GitHub both contain unique commits. Open On GitHub, use Integrate GitHub, then publish. Branchline will not overwrite either side." }
        "error" { throw "Branchline could not compare local and GitHub safely: $($tracking.error)" }
        "remote-branch-missing" { throw "The matching GitHub branch is missing and Branchline could not establish a safe relationship with the remote default branch." }
    }
    $outgoingCount = if ([int]$tracking.ahead -gt 0) { [int]$tracking.ahead } else { 1 }
    $refspec = "refs/heads/$branch`:refs/heads/$branch"
    $push = $null
    if ($tracking.hasUpstream -and $tracking.upstreamExists -and $tracking.matchingRemoteExists) {
        $push = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("push", "origin", $refspec) -DisplayCommand "git push origin $branch" -TimeoutSeconds 120
    }
    else {
        $push = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("push", "--set-upstream", "origin", $refspec) -DisplayCommand "git push --set-upstream origin $branch" -TimeoutSeconds 120
    }
    if (-not $push.ok) {
        return New-AppResult -Ok $false -Code $push.code -Command "publish $branch" -Output (Join-CommandOutput @($fetch.output, $push.output, "No local commit was removed. Check GitHub, integrate incoming work if necessary, then publish again.")) -Phase "publish" -Steps @(
            (New-ActionStep "Check GitHub" "completed" "git fetch origin" $fetch.output),
            (New-ActionStep "Publish commits" "failed" $push.command $push.output)
        ) -Recovery @{ nextAction = "fetch"; localCommitsPreserved = $true }
    }
    $after = Get-WorkingTreeState $RepoPath
    $remaining = if ($after.ok) { @($after.files).Count } else { -1 }
    $remainingText = if ($remaining -ge 0) { "$remaining uncommitted file change$(if ($remaining -eq 1) { '' } else { 's' }) remain$(if ($remaining -eq 1) { 's' } else { '' }) on this computer." } else { "Branchline could not re-read remaining local file changes after publishing." }
    return New-AppResult -Ok $true -Command "publish $branch" -Output (Join-CommandOutput @($fetch.output, $push.output, "$outgoingCount commit$(if ($outgoingCount -eq 1) { '' } else { 's' }) published to origin/$branch.", $remainingText)) -Data @{ publishedCommits = $outgoingCount; remainingLocalChanges = $remaining } -Phase "complete" -Steps @(
        (New-ActionStep "Check GitHub" "completed" "git fetch origin" $fetch.output),
        (New-ActionStep "Publish commits" "completed" $push.command $push.output)
    )
}

function Invoke-IntegrateRemoteBranch {
    param([string]$RepoPath, [string]$Confirmation)
    [void](Assert-OriginAllowed $RepoPath)
    if (-not (Test-CleanWorkingTree $RepoPath)) {
        throw "Commit or restore every local change before integrating GitHub. Staging alone is not enough. Nothing was changed."
    }
    $operation = Get-GitOperationState $RepoPath
    if (-not [string]::IsNullOrWhiteSpace($operation)) { throw "Finish or abort the active $operation before integrating GitHub." }
    $branch = Get-CurrentBranch $RepoPath
    if (-not (Test-BranchName -RepoPath $RepoPath -Branch $branch)) { throw "The current branch cannot be integrated." }

    $fetch = Invoke-OriginFetch -RepoPath $RepoPath -DisplayCommand "check GitHub before integration"
    if (-not $fetch.ok) { return $fetch }
    $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch $branch
    switch ([string]$tracking.relationship) {
        "in-sync" { return New-AppResult -Ok $true -Command "integrate origin/$branch" -Output (Join-CommandOutput @($fetch.output, "Local and GitHub already agree. Nothing was changed.")) }
        "ahead" { return New-AppResult -Ok $true -Command "integrate origin/$branch" -Output (Join-CommandOutput @($fetch.output, "There are no incoming commits. Your local commits are ready to publish.")) }
        "behind" {
            $fastForward = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("merge", "--ff-only", "refs/remotes/origin/$branch") -DisplayCommand "fast-forward from origin/$branch" -TimeoutSeconds 60
            return New-AppResult -Ok $fastForward.ok -Code $fastForward.code -Command "pull origin/$branch" -Output (Join-CommandOutput @($fetch.output, $fastForward.output)) -Phase $(if ($fastForward.ok) { "complete" } else { "fast-forward" }) -Steps @(
                (New-ActionStep "Check GitHub" "completed" $fetch.command $fetch.output),
                (New-ActionStep "Fast-forward local branch" $(if ($fastForward.ok) { "completed" } else { "failed" }) $fastForward.command $fastForward.output)
            ) -Recovery $(if ($fastForward.ok) { @{} } else { @{ nextAction = "fetch"; localFilesPreserved = $true } })
        }
        "unrelated" { throw "Integration is blocked because the local project and GitHub repository have unrelated histories." }
        "local-empty" { throw "Bring GitHub history here before integrating branches." }
        "unpublished" { throw "The current branch does not exist on GitHub yet. Publish it instead." }
        "remote-empty" { throw "GitHub is empty. Publish the local branch instead." }
        "error" { throw "Branchline could not compare the branches safely: $($tracking.error)" }
    }
    if ([string]$tracking.relationship -ne "diverged") { throw "There are no GitHub commits to integrate into this branch." }
    if ($Confirmation -cne "MERGE_REMOTE:$branch") { throw "Integration confirmation was missing." }

    $merge = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("merge", "--no-edit", "refs/remotes/origin/$branch") -DisplayCommand "merge origin/$branch into $branch" -TimeoutSeconds 120
    $guidance = if ($merge.ok) {
        "Both histories are now preserved locally. Review the merge, then publish $branch."
    } elseif ((Get-GitOperationState $RepoPath) -eq "merge") {
        "The merge paused because files conflict. Resolve each conflicted file, stage the resolutions, and commit; or use Abort operation to return safely."
    } else {
        "Git did not complete the integration. No force push or history rewrite was attempted."
    }
    return New-AppResult -Ok $merge.ok -Code $merge.code -Command "integrate origin/$branch" -Output (Join-CommandOutput @($fetch.output, $merge.output, $guidance)) -Phase $(if ($merge.ok) { "complete" } else { "merge" }) -Steps @(
        (New-ActionStep "Check GitHub" "completed" $fetch.command $fetch.output),
        (New-ActionStep "Merge GitHub history" $(if ($merge.ok) { "completed" } else { "needs-attention" }) $merge.command $merge.output)
    ) -Partial (-not $merge.ok -and (Get-GitOperationState $RepoPath) -eq "merge") -Recovery $(if ($merge.ok) { @{} } else { @{ nextAction = "resolve-conflicts-or-abort"; localFilesPreserved = $true } })
}

function Start-GitHubLogin {
    param([string]$RepoPath)
    $origin = Assert-OriginAllowed $RepoPath
    if ($origin.type -ne "github") { throw "Browser login is available only for GitHub remotes." }
    $arguments = @("credential-manager", "github", "login", "--url", "https://github.com", "--username", $origin.owner, "--force", "--browser")
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:AppState.GitPath
    $info.Arguments = ($arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument ([string]$_) }) -join " "
    $info.WorkingDirectory = $RepoPath
    $info.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($info)
    return New-AppResult -Ok $true -Code 0 -Command "GitHub login" -Output "A GitHub sign-in window was opened for $($origin.owner). Finish signing in, then publish again."
}

$repositoryQueriesPath = Join-Path $PSScriptRoot "private\RepositoryQueries.ps1"
if (-not (Test-Path -LiteralPath $repositoryQueriesPath -PathType Leaf)) { throw "Branchline repository query module is missing." }
. $repositoryQueriesPath
$repositoryStatePath = Join-Path $PSScriptRoot "private\RepositoryState.ps1"
if (-not (Test-Path -LiteralPath $repositoryStatePath -PathType Leaf)) { throw "Branchline repository state helpers are missing." }
. $repositoryStatePath

function Get-LocalStatusSummary {
    if ([string]::IsNullOrWhiteSpace($script:AppState.RepoPath) -or -not (Test-GitRepository $script:AppState.RepoPath)) {
        return [pscustomobject]@{ ok = $false; configured = $false; stateOk = $true; stateError = ""; branch = ""; headState = "none"; headCommit = ""; upstream = ""; ahead = 0; behind = 0; operation = ""; changedCount = 0; stagedCount = 0; changedFiles = @(); signature = ""; localScannedAt = ""; durationSeconds = 0; scanDurationMs = 0; revisions = @{ repository = ""; local = ""; head = ""; config = ""; localRefs = ""; remoteRefs = "" } }
    }
    $repo = $script:AppState.RepoPath
    $health = Get-RepositoryHealthSnapshot $repo -Force
    $working = $health.working
    $head = $health.head
    $files = @(if ($working.ok) { @($working.files) } else { @() })
    $revisions = [pscustomobject]@{ repository = ""; local = ""; head = ""; config = ""; localRefs = ""; remoteRefs = "" }
    $revisionError = ""
    if ($working.ok) {
        try { $revisions = Get-RepositoryRevisions -RepoPath $repo -WorkingState $working }
        catch { $revisionError = $_.Exception.Message }
    }
    return [pscustomobject]@{
        ok = $true
        configured = $true
        stateOk = ([bool]$health.ok -and [string]::IsNullOrWhiteSpace($revisionError))
        stateError = (Join-CommandOutput @([string]$health.error, $revisionError))
        branch = [string]$head.branch
        headState = [string]$head.state
        headCommit = [string]$head.commit
        upstream = [string]$working.upstream
        ahead = [int]$working.ahead
        behind = [int]$working.behind
        operation = [string]$health.operation
        changedCount = $files.Count
        stagedCount = @($files | Where-Object { $_.state -in @("staged", "mixed") }).Count
        changedFiles = @($files | Select-Object -First 500)
        truncated = ($files.Count -gt 500)
        signature = [string]$working.signature
        localScannedAt = [string]$working.scannedAt
        durationSeconds = [double]$working.durationSeconds
        scanDurationMs = [double]$working.durationMilliseconds
        revisions = $revisions
    }
}

function Get-AppSummaryLegacy {
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $emptySnapshot = [pscustomobject]@{ available = $false; branch = ""; files = @(); fileCount = 0; truncated = $false; incomingFiles = @(); incomingCommits = @(); outgoingCommits = @() }
    if ([string]::IsNullOrWhiteSpace($script:AppState.RepoPath)) {
        $folder = Get-FolderState $script:AppState.SelectedPath
        return [pscustomobject]@{
            ok = $false; configured = $false; isRepo = $false; folderSelected = $folder.selected; selectedPath = $folder.path; repoPath = $folder.path; folder = $folder; message = $script:AppState.StartupMessage
            stateOk = $true; stateError = ""; headState = "none"; headCommit = ""; branch = ""; remote = ""; remoteWebUrl = ""; remoteType = "none"; remoteValid = $false
            tracking = @{ hasUpstream = $false; upstream = ""; upstreamExists = $false; ahead = 0; behind = 0; mismatch = $false; relationship = "no-repository"; error = "" }
            identity = @{ configured = $false; name = ""; email = ""; inheritedAvailable = $false; inheritedName = ""; inheritedEmail = ""; source = "missing" }
            remoteSnapshot = $emptySnapshot
            changedFiles = @(); files = @(); fileCount = 0; filesTruncated = $false; branches = @(); remoteBranches = @(); defaultBranch = ""; commits = @(); operation = ""; busy = $script:AppState.Busy
            localScannedAt = ""; remoteFetchedAt = $script:AppState.RemoteFetchedAt; localStatusSignature = ""; timestamp = $now
        }
    }

    $repoPath = $script:AppState.RepoPath
    if (-not (Test-GitRepository $repoPath)) {
        $script:AppState.SelectedPath = $repoPath
        $script:AppState.RepoPath = ""
        return Get-AppSummary
    }

    $errors = New-Object System.Collections.Generic.List[string]
    # A full summary is an explicit synchronization boundary. Always rescan the
    # working tree so edits made by an editor or the Git CLI cannot be hidden by
    # the short local-status cache.
    $health = Get-RepositoryHealthSnapshot $repoPath -Force
    $head = $health.head
    if (-not $health.ok) { $errors.Add([string]$health.error) }
    $branch = [string]$head.branch
    $branches = @()
    try { $branches = @(Get-Branches $repoPath) }
    catch { $errors.Add($_.Exception.Message) }
    $working = $health.working
    $changed = @(if ($working.ok) { @($working.files) } else { @() })
    $filesSnapshot = [pscustomobject]@{ files = @($changed); total = @($changed).Count; truncated = $false }
    if ($working.ok) {
        try { $filesSnapshot = Get-RepositoryFiles -RepoPath $repoPath -ChangedFiles $changed }
        catch { $errors.Add($_.Exception.Message) }
    }
    $origin = Get-OriginInfo $repoPath
    $tracking = [pscustomobject]@{ hasUpstream = $false; upstream = ""; upstreamExists = $false; mismatch = $false; matchingRemoteExists = $false; remoteBranch = $branch; remoteDefaultBranch = ""; remoteHasBranches = $false; remoteBranchNames = @(); hasLocalCommit = $false; ahead = 0; behind = 0; diverged = $false; relationship = if ($origin.valid) { "error" } else { "no-remote" }; error = "" }
    if ($head.state -ne "detached" -and -not [string]::IsNullOrWhiteSpace($branch)) {
        try {
            if ($origin.valid) { $tracking = Get-TrackingStatus -RepoPath $repoPath -Branch $branch -LocalBranches $branches }
            else { $tracking.hasLocalCommit = Test-GitRef -RepoPath $repoPath -Ref "refs/heads/$branch" }
        }
        catch {
            $errors.Add($_.Exception.Message)
            $tracking.relationship = "error"
            $tracking.error = $_.Exception.Message
        }
    }
    elseif ($head.state -eq "detached") {
        $tracking.relationship = "detached"
        $tracking.error = "Create a named branch before committing, pulling, or publishing."
    }
    $remoteSnapshot = $emptySnapshot
    if ($origin.valid -and $tracking.relationship -ne "error") {
        try { $remoteSnapshot = Get-RemoteSnapshot -RepoPath $repoPath -Tracking $tracking }
        catch { $errors.Add($_.Exception.Message); $tracking.relationship = "error"; $tracking.error = $_.Exception.Message }
    }
    $stateOk = ($errors.Count -eq 0)
    $stateError = ($errors -join "`n")
    return [pscustomobject]@{
        ok = $true
        configured = $true
        isRepo = $true
        stateOk = $stateOk
        stateError = $stateError
        headState = [string]$head.state
        headCommit = [string]$head.commit
        folderSelected = $true
        selectedPath = $repoPath
        folder = Get-FolderState -Path $repoPath -KnownIsRepo $true
        repoPath = $repoPath
        repoName = Split-Path -Leaf $repoPath
        message = if ($stateOk) { "Repository ready" } else { "Repository state needs attention" }
        branch = $branch
        remote = $origin.display
        remoteWebUrl = $origin.webUrl
        remoteType = $origin.type
        remoteValid = $origin.valid
        tracking = $tracking
        identity = Get-GitIdentity $repoPath
        remoteSnapshot = $remoteSnapshot
        changedFiles = @($changed)
        files = @($filesSnapshot.files)
        fileCount = $filesSnapshot.total
        filesTruncated = $filesSnapshot.truncated
        branches = $branches
        remoteBranches = @($tracking.remoteBranchNames)
        defaultBranch = [string]$tracking.remoteDefaultBranch
        commits = @(Get-RecentCommits $repoPath)
        operation = [string]$health.operation
        busy = $script:AppState.Busy
        localScannedAt = [string]$working.scannedAt
        remoteFetchedAt = $script:AppState.RemoteFetchedAt
        localStatusSignature = [string]$working.signature
        timestamp = $now
    }
}

function Get-AppSummary {
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $emptyRevisions = [pscustomobject]@{ repository = ""; local = ""; head = ""; config = ""; localRefs = ""; remoteRefs = "" }
    $emptySnapshot = [pscustomobject]@{ available = $false; branch = ""; files = @(); fileCount = 0; truncated = $false; incomingFiles = @(); incomingCommits = @(); outgoingCommits = @() }
    if ([string]::IsNullOrWhiteSpace($script:AppState.RepoPath)) {
        $folder = Get-FolderState $script:AppState.SelectedPath
        return [pscustomobject]@{
            ok = $false; configured = $false; isRepo = $false; folderSelected = $folder.selected; selectedPath = $folder.path; repoPath = $folder.path; folder = $folder; message = $script:AppState.StartupMessage
            stateOk = $true; stateError = ""; headState = "none"; headCommit = ""; branch = ""; remote = ""; remoteWebUrl = ""; remoteType = "none"; remoteValid = $false
            tracking = @{ hasUpstream = $false; upstream = ""; upstreamExists = $false; ahead = 0; behind = 0; mismatch = $false; relationship = "no-repository"; error = "" }
            identity = @{ configured = $false; name = ""; email = ""; inheritedAvailable = $false; inheritedName = ""; inheritedEmail = ""; source = "missing" }
            remoteSnapshot = $emptySnapshot; changedFiles = @(); files = @(); fileCount = 0; filesTruncated = $false; branches = @(); remoteBranches = @(); defaultBranch = ""; commits = @(); operation = ""; busy = $script:AppState.Busy
            localScannedAt = ""; remoteFetchedAt = $script:AppState.RemoteFetchedAt; localStatusSignature = ""; revisions = $emptyRevisions; timestamp = $now
        }
    }

    $repoPath = $script:AppState.RepoPath
    if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) {
        $script:AppState.SelectedPath = $repoPath
        $script:AppState.RepoPath = ""
        Reset-BranchlineQueryCache
        return Get-AppSummary
    }

    $errors = New-Object System.Collections.Generic.List[string]
    # A full summary is an explicit synchronization boundary. Always rescan the
    # working tree so edits made by an editor or the Git CLI cannot be hidden by
    # the short local-status cache.
    $health = Get-RepositoryHealthSnapshot $repoPath -Force
    $working = $health.working
    $head = $health.head
    if (-not $health.ok) { $errors.Add([string]$health.error) }
    $changed = @(if ($working.ok) { @($working.files) } else { @() })
    $revisions = $emptyRevisions
    if ($working.ok) {
        try { $revisions = Get-RepositoryRevisions -RepoPath $repoPath -WorkingState $working }
        catch { $errors.Add($_.Exception.Message) }
    }
    $summaryKey = @(
        [string]$revisions.repository, [string]$revisions.local, [string]$revisions.head,
        [string]$revisions.config, [string]$revisions.localRefs, [string]$revisions.remoteRefs,
        [string]$health.operation, [string]$script:AppState.RemoteFetchedAt
    ) -join "|"
    if ($health.ok -and $errors.Count -eq 0) {
        $cachedSummary = Get-BranchlineCacheEntry -Name "summary" -Key $summaryKey
        if ($null -ne $cachedSummary) {
            $cachedSummary.localScannedAt = [string]$working.scannedAt
            $cachedSummary.localStatusSignature = [string]$working.signature
            $cachedSummary.busy = $script:AppState.Busy
            $cachedSummary.timestamp = $now
            return $cachedSummary
        }
    }

    $branch = [string]$head.branch
    $branches = @()
    try {
        $branchesKey = "$($revisions.repository)|$($revisions.localRefs)|$($revisions.head)"
        $branches = @(Get-CachedRepositoryValue -Name "branches" -Key $branchesKey -Factory { @(Get-Branches $repoPath) } -SizeBytes 65536)
    }
    catch { $errors.Add($_.Exception.Message) }

    $origin = [pscustomobject]@{ configured = $false; valid = $false; display = ""; webUrl = ""; type = "none" }
    try {
        $originKey = "$($revisions.repository)|$($revisions.config)"
        $origin = Get-CachedRepositoryValue -Name "origin" -Key $originKey -Factory { Get-OriginInfo $repoPath } -SizeBytes 8192
    }
    catch { $errors.Add($_.Exception.Message) }

    $tracking = [pscustomobject]@{ hasUpstream = $false; upstream = ""; upstreamExists = $false; mismatch = $false; matchingRemoteExists = $false; remoteBranch = $branch; remoteDefaultBranch = ""; remoteHasBranches = $false; remoteBranchNames = @(); hasLocalCommit = $false; ahead = 0; behind = 0; diverged = $false; relationship = if ($origin.valid) { "error" } else { "no-remote" }; error = "" }
    if ($head.state -ne "detached" -and -not [string]::IsNullOrWhiteSpace($branch)) {
        try {
            if ($origin.valid) {
                $trackingKey = "$($revisions.repository)|$($revisions.head)|$($revisions.config)|$($revisions.localRefs)|$($revisions.remoteRefs)"
                $tracking = Get-CachedRepositoryValue -Name "tracking" -Key $trackingKey -Factory { Get-TrackingStatus -RepoPath $repoPath -Branch $branch -LocalBranches $branches } -SizeBytes 32768
            }
            else { $tracking.hasLocalCommit = ($head.state -eq "branch" -and -not [string]::IsNullOrWhiteSpace([string]$head.commit)) }
        }
        catch {
            $errors.Add($_.Exception.Message)
            $tracking.relationship = "error"
            $tracking.error = $_.Exception.Message
        }
    }
    elseif ($head.state -eq "detached") {
        $tracking.relationship = "detached"
        $tracking.error = "Create a named branch before committing, pulling, or publishing."
    }

    $remoteSnapshot = $emptySnapshot
    if ($origin.valid -and $tracking.relationship -ne "error") {
        try { $remoteSnapshot = Get-RemoteSnapshot -RepoPath $repoPath -Tracking $tracking -HeadCommit ([string]$head.commit) }
        catch { $errors.Add($_.Exception.Message); $tracking.relationship = "error"; $tracking.error = $_.Exception.Message }
    }

    $identity = [pscustomobject]@{ configured = $false; name = ""; email = ""; inheritedAvailable = $false; inheritedName = ""; inheritedEmail = ""; source = "missing" }
    try {
        $identityKey = "$($revisions.repository)|$($revisions.config)"
        $identity = Get-CachedRepositoryValue -Name "identity" -Key $identityKey -Factory { Get-GitIdentity $repoPath } -SizeBytes 8192
    }
    catch { $errors.Add($_.Exception.Message) }

    $commits = @()
    if ($head.state -eq "branch" -or $head.state -eq "detached") {
        try {
            $commitsKey = "$($revisions.repository)|$($head.commit)"
            $commits = @(Get-CachedRepositoryValue -Name "commits" -Key $commitsKey -Factory { @(Get-RecentCommits $repoPath) } -SizeBytes 131072)
        }
        catch { $errors.Add($_.Exception.Message) }
    }

    $localFilesKey = "$($revisions.repository)|local|$($working.signature)|$($head.commit)"
    $cachedFiles = Get-BranchlineCacheEntry -Name "local-files" -Key $localFilesKey
    $files = if ($null -ne $cachedFiles -and $null -ne $cachedFiles.PSObject.Properties["items"]) { @($cachedFiles.items | Select-Object -First 500) } else { @($changed) }
    $fileCount = if ($null -ne $cachedFiles) { [int]$cachedFiles.total } else { @($changed).Count }
    $stateOk = ($errors.Count -eq 0)
    $summary = [pscustomobject]@{
        ok = $true; configured = $true; isRepo = $true; stateOk = $stateOk; stateError = ($errors -join "`n")
        headState = [string]$head.state; headCommit = [string]$head.commit; folderSelected = $true; selectedPath = $repoPath; folder = Get-FolderState -Path $repoPath -KnownIsRepo $true
        repoPath = $repoPath; repoName = Split-Path -Leaf $repoPath; message = if ($stateOk) { "Repository ready" } else { "Repository state needs attention" }; branch = $branch
        remote = [string]$origin.display; remoteWebUrl = [string]$origin.webUrl; remoteType = [string]$origin.type; remoteValid = [bool]$origin.valid
        tracking = $tracking; identity = $identity; remoteSnapshot = $remoteSnapshot; changedFiles = $changed; files = $files; fileCount = $fileCount; filesTruncated = ($fileCount -gt 500)
        branches = $branches; remoteBranches = @($tracking.remoteBranchNames); defaultBranch = [string]$tracking.remoteDefaultBranch; commits = $commits; operation = [string]$health.operation; busy = $script:AppState.Busy
        localScannedAt = [string]$working.scannedAt; remoteFetchedAt = $script:AppState.RemoteFetchedAt; localStatusSignature = [string]$working.signature; revisions = $revisions; timestamp = $now
    }
    if ($stateOk) { Set-BranchlineCacheEntry -Name "summary" -Key $summaryKey -Value $summary -SizeBytes 524288 | Out-Null }
    return $summary
}

function Invoke-AppAction {
    param([object]$Payload)

    if ($script:AppState.Busy) {
        return New-AppResult -Ok $false -Code 1 -Command "busy" -Output "Another Git operation is still running."
    }

    $script:AppState.Busy = $true
    $action = "request"
    try {
        $action = Get-PayloadString -Payload $Payload -Name "action"
        $script:AppState.CurrentAction = $action
        $stateIndependentActions = @(Get-StateIndependentActionNames)
        if (-not [string]::IsNullOrWhiteSpace($script:AppState.RepoPath) -and $action -notin $stateIndependentActions) {
            $preflight = Get-WorkingTreeState $script:AppState.RepoPath -Force
            if (-not $preflight.ok) { throw "Repository status is unavailable, so '$action' was blocked. Repair the Git repository and refresh before changing anything.`n$($preflight.error)" }
        }
        switch ($action) {
            "selectRepository" {
                $path = Resolve-SafeDirectory (Get-PayloadString $Payload "path")
                $script:AppState.SelectedPath = $path
                $root = Get-GitRepositoryRoot $path
                if ([string]::IsNullOrWhiteSpace($root)) {
                    $script:AppState.RepoPath = ""
                    $script:AppState.StartupMessage = "This is a normal folder. Make it a Git repository, or clone GitHub here if the folder is empty."
                    Save-LastRepository
                    return New-AppResult -Ok $true -Command "inspect folder" -Output "Normal folder selected: $path`nChoose Make Git repository, or enter a GitHub URL and clone into this empty folder." -Data @{ isRepo = $false }
                }
                $script:AppState.RepoPath = $root
                $script:AppState.SelectedPath = $root
                Save-LastRepository
                return New-AppResult -Ok $true -Command "select repository" -Output "Loaded repository: $root" -Data @{ isRepo = $true }
            }
            "initializeRepository" {
                if ((Get-PayloadString $Payload "confirm") -ne "INITIALIZE") { throw "Initialization confirmation was missing." }
                $path = Resolve-SafeDirectory (Get-PayloadString $Payload "path")
                if (Test-GitRepository $path) { throw "That folder is already a Git repository." }
                $init = Invoke-GitCommand -WorkingDirectory $path -Arguments @("init", "-b", "main") -DisplayCommand "git init -b main" -TimeoutSeconds 30
                if (-not $init.ok) { return $init }
                $script:AppState.RepoPath = $path
                $script:AppState.SelectedPath = $path
                Save-LastRepository
                return $init
            }
            "cloneRepository" {
                if ((Get-PayloadString $Payload "confirm") -ne "CLONE") { throw "Clone confirmation was missing." }
                $path = Resolve-SafeDirectory (Get-PayloadString $Payload "path")
                if (Test-GitRepository $path) { throw "That folder is already a Git repository." }
                $folder = Get-FolderState $path
                if (-not $folder.empty) { throw "Cloning requires an empty folder. Choose a new empty folder, or initialize this folder if its existing files belong to the project." }
                $parsed = ConvertTo-GitHubRemoteValue -Value (Get-PayloadString $Payload "remote") -AllowLocal:$script:AppState.AllowLocalTestRemote
                if (-not $parsed.valid) { throw $parsed.message }
                $clone = Invoke-GitCommand -WorkingDirectory $path -Arguments @("clone", "--origin", "origin", "--no-tags", $parsed.gitUrl, ".") -DisplayCommand "clone GitHub repository" -TimeoutSeconds 180
                if (-not $clone.ok) { return $clone }
                $root = Get-GitRepositoryRoot $path
                if ([string]::IsNullOrWhiteSpace($root)) { throw "Git finished cloning, but the new repository could not be opened." }
                $checkoutOutput = ""
                $clonedHead = Invoke-GitCommand -WorkingDirectory $root -Arguments @("rev-parse", "--verify", "HEAD") -DisplayCommand "check cloned branch" -TimeoutSeconds 10
                if (-not $clonedHead.ok) {
                    $defaultBranch = Get-RemoteDefaultBranch $root
                    if (-not [string]::IsNullOrWhiteSpace($defaultBranch)) {
                        $checkout = Invoke-GitCommand -WorkingDirectory $root -Arguments @("switch", "-C", $defaultBranch, "--track", "origin/$defaultBranch") -DisplayCommand "check out GitHub default branch" -TimeoutSeconds 30
                        if (-not $checkout.ok) { return $checkout }
                        $checkoutOutput = $checkout.output
                    }
                }
                $script:AppState.RepoPath = $root
                $script:AppState.SelectedPath = $root
                $script:AppState.RemoteFetchedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                $script:AppState.RemoteSnapshotCache = $null
                $script:AppState.RemoteSnapshotKey = ""
                Save-LastRepository
                return New-AppResult -Ok $true -Command "clone GitHub repository" -Output (Join-CommandOutput @($clone.output, $checkoutOutput, "GitHub was cloned into: $root"))
            }
            "detachRepository" {
                $repo = Assert-RepositorySelected
                $name = Split-Path -Leaf $repo
                if ((Get-PayloadString $Payload "confirm") -cne "DETACH_GIT:$name") { throw "Detach confirmation was missing." }
                $gitMetadata = Join-Path $repo ".git"
                if (-not (Test-Path -LiteralPath $gitMetadata -PathType Container)) { throw "Only a standard .git directory can be detached safely. Linked worktrees and bare repositories are not changed." }
                $suffix = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupName = ".branchline-git-backup-$suffix"
                $counter = 1
                while (Test-Path -LiteralPath (Join-Path $repo $backupName)) { $backupName = ".branchline-git-backup-$suffix-$counter"; $counter += 1 }
                Move-Item -LiteralPath $gitMetadata -Destination (Join-Path $repo $backupName) -ErrorAction Stop
                $script:AppState.RepoPath = ""
                $script:AppState.SelectedPath = $repo
                $script:AppState.StartupMessage = "Git was detached. Your files are unchanged and the history backup can be restored."
                Save-LastRepository
                return New-AppResult -Ok $true -Command "detach local Git" -Output "The folder is now a normal folder.`nFiles were kept.`nRecoverable Git history: $backupName" -Data @{ backup = $backupName }
            }
            "restoreGitMetadata" {
                $path = Resolve-SafeDirectory (Get-PayloadString $Payload "path")
                if (Test-Path -LiteralPath (Join-Path $path ".git")) { throw "This folder already contains Git metadata." }
                $backupName = (Get-PayloadString $Payload "backup").Trim()
                if ($backupName -notmatch '^\.branchline-git-backup-\d{8}-\d{6}(?:-\d+)?$') { throw "Choose a valid Branchline Git backup." }
                if ((Get-PayloadString $Payload "confirm") -cne "RESTORE_GIT:$backupName") { throw "Restore-Git confirmation was missing." }
                $backupPath = Join-Path $path $backupName
                if (-not (Test-Path -LiteralPath $backupPath -PathType Container)) { throw "The selected Git history backup no longer exists." }
                $restoredPath = Join-Path $path ".git"
                Move-Item -LiteralPath $backupPath -Destination $restoredPath -ErrorAction Stop
                if (-not (Test-GitRepository $path)) {
                    try {
                        if (Test-Path -LiteralPath $restoredPath -PathType Container) {
                            Move-Item -LiteralPath $restoredPath -Destination $backupPath -ErrorAction Stop
                        }
                    }
                    catch {
                        throw "Git could not validate the restored metadata, and rollback also failed. The metadata remains at $restoredPath. Do not delete it."
                    }
                    throw "Git could not validate that backup. It was returned safely to $backupName and the folder remains a normal folder."
                }
                $root = Get-GitRepositoryRoot $path
                $script:AppState.RepoPath = $root
                $script:AppState.SelectedPath = $root
                Save-LastRepository
                return New-AppResult -Ok $true -Command "restore local Git" -Output "Git history was restored from $backupName."
            }
            "configureRemote" {
                $repo = Assert-RepositorySelected
                if ((Get-PayloadString $Payload "confirm") -ne "CONNECT") { throw "Remote confirmation was missing." }
                $parsed = ConvertTo-GitHubRemoteValue -Value (Get-PayloadString $Payload "remote") -AllowLocal:$script:AppState.AllowLocalTestRemote
                if (-not $parsed.valid) { throw $parsed.message }
                $previous = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("remote", "get-url", "origin") -DisplayCommand "read origin" -TimeoutSeconds 10
                $hadOrigin = $previous.ok
                $recoveryFile = Save-RemoteConfigurationRecovery $repo
                $set = if ($hadOrigin) {
                    Invoke-GitCommand -WorkingDirectory $repo -Arguments @("remote", "set-url", "origin", $parsed.gitUrl) -DisplayCommand "set GitHub origin" -TimeoutSeconds 15
                } else {
                    Invoke-GitCommand -WorkingDirectory $repo -Arguments @("remote", "add", "origin", $parsed.gitUrl) -DisplayCommand "add GitHub origin" -TimeoutSeconds 15
                }
                if (-not $set.ok) { return $set }
                $fetch = Invoke-OriginFetch -RepoPath $repo -DisplayCommand "git fetch origin"
                if (-not $fetch.ok) {
                    if ($hadOrigin) {
                        [void](Invoke-GitCommand -WorkingDirectory $repo -Arguments @("remote", "set-url", "origin", $previous.raw.Trim()) -DisplayCommand "restore previous origin" -TimeoutSeconds 15)
                    } else {
                        [void](Invoke-GitCommand -WorkingDirectory $repo -Arguments @("remote", "remove", "origin") -DisplayCommand "remove failed origin" -TimeoutSeconds 15)
                    }
                    return New-AppResult -Ok $false -Code $fetch.code -Command "connect GitHub origin" -Output (Join-CommandOutput @($fetch.output, "The previous origin configuration was restored.")) -Phase "fetch" -Steps @(
                        (New-ActionStep "Save previous connection" "completed" "write recovery journal" $recoveryFile),
                        (New-ActionStep "Set origin" "completed" $set.command $set.output),
                        (New-ActionStep "Fetch origin" "failed" $fetch.command $fetch.output),
                        (New-ActionStep "Restore previous connection" "completed" "restore origin" "The prior origin was restored.")
                    ) -Recovery @{ recoveryFile = $recoveryFile; previousOriginRestored = $true }
                }
                $originChanged = ($hadOrigin -and $previous.raw.Trim() -cne $parsed.gitUrl)
                if ($originChanged) {
                    $trackingBranches = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("for-each-ref", "--format=%(refname:short)%09%(upstream:short)", "refs/heads") -DisplayCommand "inspect old upstreams" -TimeoutSeconds 15
                    if ($trackingBranches.ok) {
                        foreach ($line in @($trackingBranches.raw -split '(?:\r\n|\n|\r)')) {
                            $parts = $line -split "`t", 2
                            if ($parts.Count -eq 2 -and $parts[1].StartsWith("origin/")) {
                                [void](Invoke-GitCommand -WorkingDirectory $repo -Arguments @("branch", "--unset-upstream", $parts[0]) -DisplayCommand "clear stale upstream for $($parts[0])" -TimeoutSeconds 10)
                            }
                        }
                    }
                }
                $relationship = (Get-TrackingStatus -RepoPath $repo -Branch (Get-CurrentBranch $repo)).relationship
                return New-AppResult -Ok $true -Command "connect GitHub origin" -Output (Join-CommandOutput @($set.output, $fetch.output, "Origin is ready for inspection: $($parsed.display)", "Previous connection recovery: $recoveryFile", "Relationship: $relationship")) -Data @{ relationship = $relationship; recoveryFile = $recoveryFile } -Phase "complete" -Steps @(
                    (New-ActionStep "Save previous connection" "completed" "write recovery journal" $recoveryFile),
                    (New-ActionStep "Set origin" "completed" $set.command $set.output),
                    (New-ActionStep "Fetch origin" "completed" $fetch.command $fetch.output)
                ) -Recovery @{ recoveryFile = $recoveryFile }
            }
            "githubLogin" { return Start-GitHubLogin (Assert-RepositorySelected) }
            "githubResetLogin" {
                $repo = Assert-RepositorySelected
                $origin = Assert-OriginAllowed $repo
                if ($origin.type -ne "github") { throw "GitHub login reset is available only for GitHub remotes." }
                $logout = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("credential-manager", "github", "logout", $origin.owner, "--url", "https://github.com", "--no-ui") -DisplayCommand "GitHub logout" -TimeoutSeconds 30
                $login = Start-GitHubLogin $repo
                return New-AppResult -Ok $login.ok -Code $login.code -Command "reset GitHub login" -Output (Join-CommandOutput @($logout.output, $login.output))
            }
            "setIdentity" {
                $repo = Assert-RepositorySelected
                $name = (Get-PayloadString $Payload "name").Trim()
                $email = (Get-PayloadString $Payload "email").Trim()
                if (-not (Test-SafeIdentityName $name)) { throw "Enter a commit author name using 1 to 100 characters, without angle brackets or line breaks." }
                if (-not (Test-SafeIdentityEmail $email)) { throw "Enter a valid commit author email address." }
                $setName = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("config", "--local", "user.name", $name) -DisplayCommand "save repository author name" -TimeoutSeconds 15
                if (-not $setName.ok) { return $setName }
                $setEmail = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("config", "--local", "user.email", $email) -DisplayCommand "save repository author email" -TimeoutSeconds 15
                if (-not $setEmail.ok) { return $setEmail }
                return New-AppResult -Ok $true -Command "save commit identity" -Output "Commits in this repository will be recorded as $name <$email>. No global Git settings were changed."
            }
            "listFiles" {
                $repo = Assert-RepositorySelected
                $side = Get-PayloadString $Payload "side"
                $query = Get-PayloadString $Payload "query"
                $offset = Get-PayloadInteger -Payload $Payload -Name "offset" -Default 0 -Minimum 0 -Maximum 1000000
                $limit = Get-PayloadInteger -Payload $Payload -Name "limit" -Default 100 -Minimum 1 -Maximum 200
                $page = Get-RepositoryFilePage -RepoPath $repo -Side $side -Query $query -Offset $offset -Limit $limit
                return New-AppResult -Ok $true -Command "browse $($page.side) files" -Output "Loaded $($page.items.Count) of $($page.total) $($page.side) files." -Data @{ page = $page }
            }
            "previewFile" {
                $repo = Assert-RepositorySelected
                $preview = Get-RepositoryFilePreview -RepoPath $repo -Side (Get-PayloadString $Payload "side") -Path (Get-PayloadString $Payload "file")
                return New-AppResult -Ok $true -Command "preview $($preview.side) file" -Output "Previewed $($preview.path)." -Data @{ preview = $preview }
            }
            "openRepositoryFolder" {
                $repo = Assert-RepositorySelected
                $explorer = Join-Path $env:SystemRoot "explorer.exe"
                if (-not (Test-Path -LiteralPath $explorer -PathType Leaf)) { throw "Windows Explorer could not be found." }
                Start-Process -FilePath $explorer -ArgumentList @($repo) | Out-Null
                return New-AppResult -Ok $true -Command "open repository folder" -Output "Opened the selected repository in Windows Explorer."
            }
            "fetch" {
                $repo = Assert-RepositorySelected
                [void](Assert-OriginAllowed $repo)
                return Invoke-OriginFetch -RepoPath $repo -DisplayCommand "git fetch origin"
            }
            "repairUpstream" {
                $repo = Assert-RepositorySelected
                [void](Assert-OriginAllowed $repo)
                $branch = Get-CurrentBranch $repo
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "Create or switch to a named branch before repairing tracking." }
                if ((Get-PayloadString $Payload "confirm") -cne "REPAIR_UPSTREAM:$branch") { throw "Tracking-repair confirmation was missing or the branch changed." }
                $fetch = Invoke-OriginFetch -RepoPath $repo -DisplayCommand "check GitHub before repairing tracking"
                if (-not $fetch.ok) { return $fetch }
                $tracking = Get-TrackingStatus -RepoPath $repo -Branch $branch
                if (-not $tracking.matchingRemoteExists) { throw "GitHub does not contain origin/$branch. Use Publish as new GitHub branch instead." }
                if (-not $tracking.mismatch -and $tracking.upstream -ceq "origin/$branch") {
                    return New-AppResult -Ok $true -Command "repair branch tracking" -Output "$branch already tracks origin/$branch. Nothing was changed."
                }
                $repair = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("branch", "--set-upstream-to=origin/$branch", $branch) -DisplayCommand "track origin/$branch" -TimeoutSeconds 30
                return New-AppResult -Ok $repair.ok -Code $repair.code -Command "repair branch tracking" -Output (Join-CommandOutput @($fetch.output, $repair.output, $(if ($repair.ok) { "$branch now tracks origin/$branch." } else { "Tracking was not changed." }))) -Phase $(if ($repair.ok) { "complete" } else { "tracking" }) -Steps @(
                    (New-ActionStep "Check GitHub" "completed" "git fetch origin" $fetch.output),
                    (New-ActionStep "Repair tracking" $(if ($repair.ok) { "completed" } else { "failed" }) "git branch --set-upstream-to" $repair.output)
                )
            }
            "publishNewBranch" {
                $repo = Assert-RepositorySelected
                $branch = Get-CurrentBranch $repo
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "Create a named branch before publishing it." }
                if ((Get-PayloadString $Payload "confirm") -cne "PUBLISH_NEW_BRANCH:$branch") { throw "New-branch publication confirmation was missing or the branch changed." }
                $fetch = Invoke-OriginFetch -RepoPath $repo -DisplayCommand "check GitHub before creating branch"
                if (-not $fetch.ok) { return $fetch }
                $tracking = Get-TrackingStatus -RepoPath $repo -Branch $branch
                if ($tracking.matchingRemoteExists) { throw "origin/$branch already exists. Use normal Publish instead." }
                if ($tracking.relationship -notin @("unpublished", "remote-empty")) { throw "Branchline cannot safely create origin/$branch from the current relationship '$($tracking.relationship)'." }
                return Invoke-PublishCurrentBranch $repo
            }
            "checkoutRemoteBranch" {
                $repo = Assert-RepositorySelected
                [void](Assert-OriginAllowed $repo)
                if (-not (Test-CleanWorkingTree $repo)) { throw "Commit or restore local changes before creating a branch from GitHub." }
                $branch = (Get-PayloadString $Payload "branch").Trim()
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "Choose a valid fetched GitHub branch." }
                if ((Get-PayloadString $Payload "confirm") -cne "TRACK_REMOTE:$branch") { throw "Remote-branch checkout confirmation was missing." }
                $fetch = Invoke-OriginFetch -RepoPath $repo -DisplayCommand "check GitHub before checking out branch"
                if (-not $fetch.ok) { return $fetch }
                if (@(Get-RemoteBranches $repo) -cnotcontains $branch) { throw "origin/$branch no longer exists. Check GitHub again." }
                if (Test-GitRef -RepoPath $repo -Ref "refs/heads/$branch") { throw "A local branch named '$branch' already exists. Switch to it instead." }
                $checkout = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("switch", "-c", $branch, "--track", "origin/$branch") -DisplayCommand "create local branch from origin/$branch" -TimeoutSeconds 30
                return New-AppResult -Ok $checkout.ok -Code $checkout.code -Command "checkout GitHub branch" -Output (Join-CommandOutput @($fetch.output, $checkout.output)) -Phase $(if ($checkout.ok) { "complete" } else { "checkout" })
            }
            "pull" {
                $repo = Assert-RepositorySelected
                [void](Assert-OriginAllowed $repo)
                if (-not (Test-CleanWorkingTree $repo)) { throw "Commit or restore every local change before pulling. Staging alone is not enough." }
                $branch = Get-CurrentBranch $repo
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "The current branch cannot be pulled." }
                $fetch = Invoke-OriginFetch -RepoPath $repo -DisplayCommand "git fetch origin"
                if (-not $fetch.ok) { return $fetch }
                $tracking = Get-TrackingStatus -RepoPath $repo -Branch $branch
                switch ([string]$tracking.relationship) {
                    "in-sync" { return New-AppResult -Ok $true -Command "pull origin/$branch" -Output "Local and GitHub already agree. Nothing was changed." }
                    "ahead" { return New-AppResult -Ok $true -Command "pull origin/$branch" -Output "There are no incoming commits. Your local commits are ready to publish." }
                    "unrelated" { throw "Pull is blocked because the local project and GitHub repository have unrelated histories." }
                    "diverged" { throw "Pull is blocked because both sides contain unique commits. Review and merge the divergence explicitly." }
                    "local-empty" { throw "This local repository has no commits. Use Clone GitHub here from an empty normal folder instead." }
                    "unpublished" { throw "The current branch does not exist on GitHub yet. Publish it instead." }
                    "remote-empty" { throw "The GitHub repository is empty. Create a local commit and publish it." }
                    "error" { throw "Branchline could not compare the branches safely: $($tracking.error)" }
                }
                if ($tracking.relationship -ne "behind") { throw "There are no safe incoming commits for this branch." }
                $merge = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("merge", "--ff-only", "refs/remotes/origin/$branch") -DisplayCommand "fast-forward from origin/$branch" -TimeoutSeconds 60
                return New-AppResult -Ok $merge.ok -Code $merge.code -Command "pull origin/$branch" -Output (Join-CommandOutput @($fetch.output, $merge.output)) -Phase $(if ($merge.ok) { "complete" } else { "fast-forward" }) -Steps @(
                    (New-ActionStep "Check GitHub" "completed" $fetch.command $fetch.output),
                    (New-ActionStep "Fast-forward local branch" $(if ($merge.ok) { "completed" } else { "failed" }) $merge.command $merge.output)
                ) -Recovery $(if ($merge.ok) { @{} } else { @{ nextAction = "fetch"; localFilesPreserved = $true } })
            }
            "integrateRemote" {
                return Invoke-IntegrateRemoteBranch -RepoPath (Assert-RepositorySelected) -Confirmation (Get-PayloadString $Payload "confirm")
            }
            "adoptRemote" {
                return Invoke-AdoptRemoteHistory -RepoPath (Assert-RepositorySelected) -Confirmation (Get-PayloadString $Payload "confirm")
            }
            "stageAll" {
                if ((Get-PayloadString $Payload "confirm") -ne "STAGE_ALL") { throw "Stage-all confirmation was missing." }
                return Invoke-GitCommand -WorkingDirectory (Assert-RepositorySelected) -Arguments @("add", "-A") -DisplayCommand "git add -A" -TimeoutSeconds 60
            }
            "stageFile" {
                $repo = Assert-RepositorySelected
                $path = Resolve-RepositoryFile -RepoPath $repo -Path (Get-PayloadString $Payload "file")
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--literal-pathspecs", "add", "--", $path) -DisplayCommand "stage $path" -TimeoutSeconds 30
            }
            "unstageFile" {
                $repo = Assert-RepositorySelected
                $path = Resolve-RepositoryFile -RepoPath $repo -Path (Get-PayloadString $Payload "file")
                $head = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("rev-parse", "--verify", "HEAD") -DisplayCommand "check first commit" -TimeoutSeconds 10
                if ($head.ok) {
                    return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--literal-pathspecs", "restore", "--staged", "--", $path) -DisplayCommand "unstage $path" -TimeoutSeconds 30
                }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--literal-pathspecs", "rm", "--cached", "--ignore-unmatch", "--", $path) -DisplayCommand "unstage $path before first commit" -TimeoutSeconds 30
            }
            "restoreFile" {
                $repo = Assert-RepositorySelected
                $path = Resolve-RepositoryFile -RepoPath $repo -Path (Get-PayloadString $Payload "file")
                if ((Get-PayloadString $Payload "confirm") -cne "RESTORE:$path") { throw "Restore confirmation was missing." }
                if (-not (Test-TrackedFile -RepoPath $repo -Path $path)) { throw "Untracked files cannot be restored because Git has no saved version." }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--literal-pathspecs", "restore", "--source=HEAD", "--staged", "--worktree", "--", $path) -DisplayCommand "restore $path from HEAD" -TimeoutSeconds 30
            }
            "restoreFileFromCommit" {
                $repo = Assert-RepositorySelected
                $path = Resolve-RepositoryFile -RepoPath $repo -Path (Get-PayloadString $Payload "file")
                $commit = Resolve-Commit -RepoPath $repo -Commit (Get-PayloadString $Payload "commit")
                if ((Get-PayloadString $Payload "confirm") -cne "RESTORE:$path`:$commit") { throw "Restore confirmation was missing." }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--literal-pathspecs", "restore", "--source=$commit", "--staged", "--worktree", "--", $path) -DisplayCommand "restore $path from commit" -TimeoutSeconds 30
            }
            "diffFile" {
                $repo = Assert-RepositorySelected
                $path = Resolve-RepositoryFile -RepoPath $repo -Path (Get-PayloadString $Payload "file")
                $staged = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--unified=3", "--staged", "--", $path) -DisplayCommand "staged diff for $path" -TimeoutSeconds 30
                $unstaged = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--unified=3", "--", $path) -DisplayCommand "working diff for $path" -TimeoutSeconds 30
                return New-AppResult -Ok ($staged.ok -and $unstaged.ok) -Code $(if ($staged.ok -and $unstaged.ok) { 0 } else { 1 }) -Command "diff $path" -Output (Limit-Text ("STAGED DIFF`n" + $(if ([string]::IsNullOrWhiteSpace($staged.output)) { "No staged changes." } else { $staged.output }) + "`n`nWORKING TREE DIFF`n" + $(if ([string]::IsNullOrWhiteSpace($unstaged.output)) { "No unstaged changes." } else { $unstaged.output })))
            }
            "commit" {
                $repo = Assert-RepositorySelected
                $message = (Get-PayloadString $Payload "message").Trim()
                if ([string]::IsNullOrWhiteSpace($message)) { throw "Write a commit message first." }
                if ($message.Length -gt 5000) { throw "Commit messages are limited to 5,000 characters." }
                Assert-CommitDoesNotForkRemoteHistory $repo
                [void](Assert-GitIdentity $repo)
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("commit", "-m", $message) -DisplayCommand "git commit -m <message>" -TimeoutSeconds 60
            }
            "push" { return Invoke-PublishCurrentBranch (Assert-RepositorySelected) }
            "commitStagedPush" {
                if ((Get-PayloadString $Payload "confirm") -ne "COMMIT_STAGED_PUSH") { throw "Commit-and-publish confirmation was missing." }
                $repo = Assert-RepositorySelected
                $message = (Get-PayloadString $Payload "message").Trim()
                if ([string]::IsNullOrWhiteSpace($message)) { throw "Write a commit message first." }
                if ($message.Length -gt 5000) { throw "Commit messages are limited to 5,000 characters." }
                Assert-CommitDoesNotForkRemoteHistory $repo
                [void](Assert-GitIdentity $repo)
                $stagedCheck = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("diff", "--cached", "--quiet") -DisplayCommand "check staged changes" -TimeoutSeconds 30
                if ($stagedCheck.code -eq 0) { throw "No staged changes are waiting. Stage at least one file first." }
                if ($stagedCheck.code -ne 1) { return $stagedCheck }
                $commit = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("commit", "-m", $message) -DisplayCommand "git commit staged -m <message>" -TimeoutSeconds 60
                if (-not $commit.ok) { return $commit }
                $commitIdResult = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("rev-parse", "HEAD") -DisplayCommand "identify created commit" -TimeoutSeconds 10
                $commitId = if ($commitIdResult.ok) { $commitIdResult.raw.Trim() } else { "" }
                $push = Invoke-PublishCurrentBranch $repo
                $steps = @((New-ActionStep "Create commit" "completed" $commit.command $commit.output)) + @($push.steps)
                if ($push.ok) {
                    return New-AppResult -Ok $true -Code 0 -Command "commit staged and publish" -Output (Join-CommandOutput @($commit.output, $push.output)) -Data @{ commitCreated = $true; commitId = $commitId; pushSucceeded = $true; publishedCommits = $push.publishedCommits; remainingLocalChanges = $push.remainingLocalChanges } -Phase "complete" -Steps $steps
                }
                return New-AppResult -Ok $false -Code $push.code -Command "commit staged and publish" -Output (Join-CommandOutput @($commit.output, "The commit was created successfully, but Publish did not complete.", $push.output)) -Data @{ commitCreated = $true; commitId = $commitId; pushSucceeded = $false } -Partial $true -Phase "publish" -Steps $steps -Recovery @{ nextAction = "fetch"; localCommitPreserved = $true; commitId = $commitId }
            }
            "createBranch" {
                $repo = Assert-RepositorySelected
                $branch = (Get-PayloadString $Payload "branch").Trim()
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "Enter a valid Git branch name." }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("switch", "-c", $branch) -DisplayCommand "create branch $branch" -TimeoutSeconds 30
            }
            "switchBranch" {
                $repo = Assert-RepositorySelected
                $branch = (Get-PayloadString $Payload "branch").Trim()
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "Choose a valid local branch." }
                if (-not (Test-GitRef -RepoPath $repo -Ref "refs/heads/$branch")) { throw "The selected local branch does not exist." }
                $from = Get-CurrentBranch $repo
                if ($branch -eq $from) { return New-AppResult -Ok $true -Command "switch to $branch" -Output "$branch is already the current branch." }
                $carryingChanges = -not (Test-CleanWorkingTree $repo)
                $switch = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("switch", $branch) -DisplayCommand "switch to $branch" -TimeoutSeconds 30
                $guidance = if ($switch.ok -and $carryingChanges) {
                    "The uncommitted changes moved with you from $from to $branch. Review them before committing."
                } elseif (-not $switch.ok -and $carryingChanges) {
                    "Git refused the switch because those local changes cannot be applied safely on $branch. You remain on $from and no local file was discarded."
                } else { "" }
                return New-AppResult -Ok $switch.ok -Code $switch.code -Command "switch to $branch" -Output (Join-CommandOutput @($switch.output, $guidance))
            }
            "deleteBranch" {
                $repo = Assert-RepositorySelected
                $branch = (Get-PayloadString $Payload "branch").Trim()
                if (-not (Test-BranchName -RepoPath $repo -Branch $branch)) { throw "Choose a valid local branch." }
                $current = Get-CurrentBranch $repo
                $default = Get-RemoteDefaultBranch $repo
                if ($branch -eq $current -or $branch -eq "main" -or $branch -eq "master" -or (-not [string]::IsNullOrWhiteSpace($default) -and $branch -eq $default)) { throw "The current or default branch cannot be deleted." }
                if ((Get-PayloadString $Payload "confirm") -cne "DELETE:$branch") { throw "Branch deletion confirmation was missing." }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("branch", "-d", $branch) -DisplayCommand "delete local branch $branch" -TimeoutSeconds 30
            }
            "mergeBranches" {
                $repo = Assert-RepositorySelected
                $source = (Get-PayloadString $Payload "source").Trim()
                $target = (Get-PayloadString $Payload "target").Trim()
                if (-not (Test-BranchName -RepoPath $repo -Branch $source) -or -not (Test-GitRef -RepoPath $repo -Ref "refs/heads/$source")) { throw "Choose a valid local source branch." }
                if (-not (Test-BranchName -RepoPath $repo -Branch $target) -or -not (Test-GitRef -RepoPath $repo -Ref "refs/heads/$target")) { throw "Choose a valid local target branch." }
                if ($source -eq $target) { throw "Source and target branches must be different." }
                if (-not (Test-CleanWorkingTree $repo)) { throw "Commit or restore every local change before merging branches." }
                $operation = Get-GitOperationState $repo
                if (-not [string]::IsNullOrWhiteSpace($operation)) { throw "Finish or abort the active $operation before merging branches." }
                if ((Get-PayloadString $Payload "confirm") -cne "MERGE_BRANCHES:$source`:$target") { throw "Merge confirmation was missing or the route changed." }

                $switchOutput = ""
                if ((Get-CurrentBranch $repo) -ne $target) {
                    $switch = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("switch", $target) -DisplayCommand "switch to merge target $target" -TimeoutSeconds 30
                    if (-not $switch.ok) { return $switch }
                    $switchOutput = $switch.output
                }
                $merge = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("merge", "--no-ff", "--no-edit", $source) -DisplayCommand "merge $source into $target" -TimeoutSeconds 120
                $guidance = if ($merge.ok) {
                    "$source is now merged into $target. Review the result, then publish $target when ready."
                } elseif ((Get-GitOperationState $repo) -eq "merge") {
                    "The merge paused on $target because files conflict. Resolve and stage them, then commit; or abort the merge safely."
                } else {
                    "Git did not complete the merge. No history was force-rewritten."
                }
                return New-AppResult -Ok $merge.ok -Code $merge.code -Command "merge $source into $target" -Output (Join-CommandOutput @($switchOutput, $merge.output, $guidance))
            }
            "showCommit" {
                $repo = Assert-RepositorySelected
                $commit = Resolve-Commit -RepoPath $repo -Commit (Get-PayloadString $Payload "commit")
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("--no-pager", "show", "--stat", "--oneline", "--decorate", "--no-ext-diff", $commit) -DisplayCommand "show commit $($commit.Substring(0, 8))" -TimeoutSeconds 30
            }
            "revertCommit" {
                $repo = Assert-RepositorySelected
                $commit = Resolve-Commit -RepoPath $repo -Commit (Get-PayloadString $Payload "commit")
                if (-not (Test-CleanWorkingTree $repo)) { throw "Commit or restore local changes before reverting." }
                if ((Get-PayloadString $Payload "confirm") -cne "REVERT:$commit") { throw "Revert confirmation was missing." }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments @("revert", "--no-edit", $commit) -DisplayCommand "revert commit $($commit.Substring(0, 8))" -TimeoutSeconds 120
            }
            "abortOperation" {
                $repo = Assert-RepositorySelected
                $operation = Get-GitOperationState $repo
                if ([string]::IsNullOrWhiteSpace($operation)) { throw "No interrupted Git operation is active." }
                if ((Get-PayloadString $Payload "confirm") -cne "ABORT:$operation") { throw "Abort confirmation was missing." }
                $arguments = switch ($operation) {
                    "merge" { @("merge", "--abort") }
                    "revert" { @("revert", "--abort") }
                    "cherry-pick" { @("cherry-pick", "--abort") }
                    "rebase" { @("rebase", "--abort") }
                    default { throw "That Git operation cannot be aborted here." }
                }
                return Invoke-GitCommand -WorkingDirectory $repo -Arguments $arguments -DisplayCommand "abort interrupted $operation" -TimeoutSeconds 60
            }
            "resetToCommit" {
                $repo = Assert-RepositorySelected
                $commit = Resolve-Commit -RepoPath $repo -Commit (Get-PayloadString $Payload "commit")
                if ((Get-PayloadString $Payload "confirm") -cne "RESET:$commit") { throw "Reset confirmation was missing." }
                if (-not (Test-CleanWorkingTree $repo)) { throw "Commit or restore local changes before resetting. The safety reference protects commits, not uncommitted files." }
                $save = New-SafetyReference -RepoPath $repo -Target "HEAD"
                if (-not $save.ok) { return $save }
                $reset = Invoke-GitCommand -WorkingDirectory $repo -Arguments @("reset", "--hard", $commit) -DisplayCommand "reset to $($commit.Substring(0, 8))" -TimeoutSeconds 60
                return New-AppResult -Ok $reset.ok -Code $reset.code -Command "safe hard reset" -Output (Join-CommandOutput @($save.output, $reset.output)) -Data @{ backupRef = $save.backupRef } -Phase $(if ($reset.ok) { "complete" } else { "reset" }) -Steps @(
                    (New-ActionStep "Create recovery reference" "completed" "git update-ref" $save.output),
                    (New-ActionStep "Reset branch" $(if ($reset.ok) { "completed" } else { "failed" }) "git reset --hard" $reset.output)
                ) -Recovery @{ backupRef = $save.backupRef }
            }
            default { throw "Unknown action." }
        }
    }
    catch {
        return New-AppResult -Ok $false -Code 1 -Command $action -Output $_.Exception.Message -Phase $action
    }
    finally {
        $scope = Get-ActionRefreshScope -Action $action
        Clear-BranchlineCachesForScope -Scope $scope
        $script:AppState.CurrentAction = ""
        $script:AppState.Busy = $false
    }
}

function ConvertTo-JsonText {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 10 -Compress)
}

function New-HttpResponse {
    param(
        [int]$Status = 200,
        [string]$Body = "",
        [string]$ContentType = "application/json; charset=utf-8"
    )

    $reasons = @{ 200 = "OK"; 204 = "No Content"; 400 = "Bad Request"; 401 = "Unauthorized"; 403 = "Forbidden"; 404 = "Not Found"; 405 = "Method Not Allowed"; 409 = "Conflict"; 413 = "Payload Too Large"; 415 = "Unsupported Media Type"; 429 = "Too Many Requests"; 500 = "Internal Server Error"; 503 = "Service Unavailable" }
    $reason = if ($reasons.ContainsKey($Status)) { $reasons[$Status] } else { "OK" }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $headers = @(
        "HTTP/1.1 $Status $reason",
        "Content-Type: $ContentType",
        "Content-Length: $($bodyBytes.Length)",
        "Cache-Control: no-store, max-age=0",
        "Pragma: no-cache",
        "X-Content-Type-Options: nosniff",
        "X-Frame-Options: DENY",
        "Referrer-Policy: no-referrer",
        "Permissions-Policy: camera=(), microphone=(), geolocation=()",
        "Cross-Origin-Resource-Policy: same-origin",
        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        "Connection: close",
        "",
        ""
    ) -join "`r`n"
    return @{ Header = [System.Text.Encoding]::ASCII.GetBytes($headers); Body = $bodyBytes }
}

function Find-HeaderEnd {
    param([byte[]]$Bytes)
    for ($index = 0; $index -le $Bytes.Length - 4; $index += 1) {
        if ($Bytes[$index] -eq 13 -and $Bytes[$index + 1] -eq 10 -and $Bytes[$index + 2] -eq 13 -and $Bytes[$index + 3] -eq 10) {
            return $index
        }
    }
    return -1
}

function Read-HttpRequest {
    param([System.Net.Sockets.NetworkStream]$Stream)

    $buffer = New-Object byte[] 4096
    $memory = New-Object System.IO.MemoryStream
    $headerEnd = -1
    try {
        while ($headerEnd -lt 0) {
            $read = $Stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { throw "Connection closed before the request was complete." }
            $memory.Write($buffer, 0, $read)
            if ($memory.Length -gt ($script:MaxHeaderBytes + $script:MaxBodyBytes)) { throw "Request is too large." }
            $allBytes = $memory.ToArray()
            $headerEnd = Find-HeaderEnd $allBytes
            if ($headerEnd -lt 0 -and $memory.Length -gt $script:MaxHeaderBytes) { throw "Request headers are too large." }
        }

        $allBytes = $memory.ToArray()
        $headerBytes = New-Object byte[] $headerEnd
        [Array]::Copy($allBytes, 0, $headerBytes, 0, $headerEnd)
        $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes)
        $lines = @($headerText -split '(?:\r\n|\n|\r)')
        if ($lines.Count -lt 1) { throw "Request line is missing." }
        $requestParts = @($lines[0] -split ' ')
        if ($requestParts.Count -ne 3) { throw "Request line is invalid." }
        $method = $requestParts[0].ToUpperInvariant()
        if ($method -notin @("GET", "POST", "OPTIONS")) { throw "Request method is not supported." }
        $target = $requestParts[1]
        if ($target.Length -gt 2048 -or -not $target.StartsWith("/")) { throw "Request target is invalid." }

        $headers = @{}
        foreach ($line in $lines | Select-Object -Skip 1) {
            $separator = $line.IndexOf(":")
            if ($separator -le 0) { throw "Request header is invalid." }
            $name = $line.Substring(0, $separator).Trim().ToLowerInvariant()
            $value = $line.Substring($separator + 1).Trim()
            if ($headers.ContainsKey($name)) { throw "Duplicate request headers are not accepted." }
            $headers[$name] = $value
        }
        if ($headers.ContainsKey("transfer-encoding")) { throw "Transfer-Encoding is not supported." }

        $contentLength = 0
        if ($headers.ContainsKey("content-length")) {
            if (-not [int]::TryParse($headers["content-length"], [ref]$contentLength) -or $contentLength -lt 0) { throw "Content-Length is invalid." }
        }
        if ($contentLength -gt $script:MaxBodyBytes) { throw "Request body is too large." }

        $bodyBytes = New-Object byte[] $contentLength
        $bodyStart = $headerEnd + 4
        $buffered = [Math]::Min($contentLength, $allBytes.Length - $bodyStart)
        if ($buffered -gt 0) { [Array]::Copy($allBytes, $bodyStart, $bodyBytes, 0, $buffered) }
        $offset = $buffered
        while ($offset -lt $contentLength) {
            $read = $Stream.Read($bodyBytes, $offset, $contentLength - $offset)
            if ($read -le 0) { throw "Connection closed before the request body was complete." }
            $offset += $read
        }

        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $body = if ($contentLength -gt 0) { $utf8.GetString($bodyBytes) } else { "" }
        return @{ Method = $method; Path = ($target -split '\?', 2)[0]; Headers = $headers; Body = $body }
    }
    finally {
        $memory.Dispose()
    }
}

function Test-RequestSecurity {
    param([hashtable]$Request)
    $allowedHosts = @("127.0.0.1:$($script:AppState.Port)", "localhost:$($script:AppState.Port)")
    if (-not $Request.Headers.ContainsKey("host") -or $Request.Headers["host"] -notin $allowedHosts) { return "host" }
    if ($Request.Headers.ContainsKey("origin")) {
        $allowedOrigins = @("http://127.0.0.1:$($script:AppState.Port)", "http://localhost:$($script:AppState.Port)")
        if ($Request.Headers["origin"] -notin $allowedOrigins) { return "origin" }
    }
    if ($Request.Headers.ContainsKey("sec-fetch-site") -and $Request.Headers["sec-fetch-site"] -notin @("same-origin", "none")) { return "fetch-site" }
    if (-not $Request.Headers.ContainsKey("x-git-control-token") -or $Request.Headers["x-git-control-token"] -cne $script:AppState.Token) { return "token" }
    return ""
}

$localServerPath = Join-Path $PSScriptRoot "private\LocalServer.ps1"
if (-not (Test-Path -LiteralPath $localServerPath -PathType Leaf)) { throw "Branchline local server helpers are missing." }
. $localServerPath

function Handle-HttpRequest {
    param([hashtable]$Request)
    try {
        if ($Request.Method -eq "GET" -and $Request.Path -eq "/") {
            return New-HttpResponse -Body $script:AppState.IndexHtml -ContentType "text/html; charset=utf-8"
        }
        if ($Request.Method -eq "GET" -and $Request.Path -eq "/styles.css") {
            return New-HttpResponse -Body $script:AppState.StylesCss -ContentType "text/css; charset=utf-8"
        }
        if ($Request.Method -eq "GET" -and $Request.Path -eq "/app.js") {
            return New-HttpResponse -Body $script:AppState.AppJavaScript -ContentType "application/javascript; charset=utf-8"
        }
        if ($Request.Method -eq "GET" -and $script:AppState.ExtraAssets.ContainsKey($Request.Path)) {
            return New-HttpResponse -Body ([string]$script:AppState.ExtraAssets[$Request.Path]) -ContentType "application/javascript; charset=utf-8"
        }
        if ($Request.Method -eq "GET" -and $Request.Path -eq "/api/about") {
            return New-HttpResponse -Body (ConvertTo-JsonText (New-BranchlineAboutPayload))
        }
        if ($Request.Method -eq "OPTIONS") {
            return New-HttpResponse -Status 405 -Body (ConvertTo-JsonText @{ ok = $false; message = "Cross-origin requests are not allowed." })
        }
        if ($Request.Path.StartsWith("/api/")) {
            $securityFailure = Test-RequestSecurity $Request
            if (-not [string]::IsNullOrEmpty($securityFailure)) {
                $status = if ($securityFailure -eq "token") { 401 } else { 403 }
                return New-HttpResponse -Status $status -Body (ConvertTo-JsonText @{ ok = $false; message = "Request was not authorized." })
            }
        }
        if ($Request.Method -eq "GET" -and $Request.Path -eq "/api/summary") {
            return New-HttpResponse -Body (ConvertTo-JsonText (Get-AppSummary))
        }
        if ($Request.Method -eq "GET" -and $Request.Path -eq "/api/local-status") {
            return New-HttpResponse -Body (ConvertTo-JsonText (Get-LocalStatusSummary))
        }
        if ($Request.Method -eq "POST" -and $Request.Path -eq "/api/action") {
            if (-not $Request.Headers.ContainsKey("content-type") -or -not $Request.Headers["content-type"].StartsWith("application/json", [System.StringComparison]::OrdinalIgnoreCase)) {
                return New-HttpResponse -Status 415 -Body (ConvertTo-JsonText @{ ok = $false; message = "Content-Type must be application/json." })
            }
            $payload = if ([string]::IsNullOrWhiteSpace($Request.Body)) { [pscustomobject]@{} } else { $Request.Body | ConvertFrom-Json }
            return New-HttpResponse -Body (ConvertTo-JsonText (Invoke-AppAction $payload))
        }
        return New-HttpResponse -Status 404 -Body (ConvertTo-JsonText @{ ok = $false; message = "Not found." })
    }
    catch {
        Write-Warning $_.Exception.Message
        return New-HttpResponse -Status 500 -Body (ConvertTo-JsonText @{ ok = $false; message = "The local application encountered an unexpected error." })
    }
}

function Initialize-GitControlState {
    param(
        [string]$RepoPath,
        [int]$Port,
        [string]$WebRoot,
        [string]$ProjectRoot = "",
        [string]$InstallId = "",
        [switch]$AllowLocalTestRemote
    )

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw "Git for Windows is not installed or is not available on PATH." }
    $resolvedWebRoot = [System.IO.Path]::GetFullPath($WebRoot)
    $resolvedProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { Split-Path -Parent $resolvedWebRoot } else { [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') }
    foreach ($asset in @("index.html", "styles.css", "branchline-api.js", "branchline-state.js", "branchline-render.js", "branchline-actions.js", "branchline-a11y.js", "app.js")) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedWebRoot $asset) -PathType Leaf)) { throw "Web asset is missing: $asset" }
    }
    $manifestPath = Join-Path $resolvedProjectRoot "app.manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Application manifest is missing." }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.appId -cne "branchline" -or [string]::IsNullOrWhiteSpace([string]$manifest.version)) { throw "Application manifest is invalid." }
    $runtimePath = Join-Path $resolvedProjectRoot ".runtime"
    [System.IO.Directory]::CreateDirectory($runtimePath) | Out-Null
    $installIdPath = Join-Path $runtimePath "install-id"
    if ([string]::IsNullOrWhiteSpace($InstallId)) {
        if (Test-Path -LiteralPath $installIdPath -PathType Leaf) { $InstallId = ([System.IO.File]::ReadAllText($installIdPath)).Trim() }
        if ($InstallId -notmatch '^[a-f0-9]{32}$') {
            $InstallId = [Guid]::NewGuid().ToString("N")
            [System.IO.File]::WriteAllText($installIdPath, $InstallId, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
    if ($InstallId -notmatch '^[a-f0-9]{32}$') { throw "Installation identity is invalid." }

    $script:AppState.Port = $Port
    $script:AppState.GitPath = $git.Source
    $script:AppState.WebRoot = $resolvedWebRoot
    $script:AppState.ProjectRoot = $resolvedProjectRoot
    $script:AppState.InstallId = $InstallId
    $script:AppState.Version = [string]$manifest.version
    $script:AppState.ProtocolVersion = [int]$manifest.protocolVersion
    $script:AppState.RuntimePath = $runtimePath
    $script:AppState.Token = New-SessionToken
    $script:AppState.ProcessStartedAtUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString("o")
    $script:AppState.RuntimeStateCheckedAt = [DateTime]::MinValue
    $script:AppState.AllowLocalTestRemote = [bool]$AllowLocalTestRemote
    $localAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { [System.IO.Path]::GetTempPath() } else { $env:LOCALAPPDATA }
    $script:AppState.ConfigPath = Join-Path $localAppData "GitControlPanel\config.json"
    $script:AppState.StylesCss = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "styles.css") -Encoding UTF8
    $script:AppState.AppJavaScript = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "app.js") -Encoding UTF8
    $script:AppState.ExtraAssets = @{
        "/branchline-api.js" = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "branchline-api.js") -Encoding UTF8
        "/branchline-state.js" = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "branchline-state.js") -Encoding UTF8
        "/branchline-render.js" = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "branchline-render.js") -Encoding UTF8
        "/branchline-actions.js" = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "branchline-actions.js") -Encoding UTF8
        "/branchline-a11y.js" = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "branchline-a11y.js") -Encoding UTF8
    }
    $index = Get-Content -Raw -LiteralPath (Join-Path $resolvedWebRoot "index.html") -Encoding UTF8
    if (-not $index.Contains("{{SESSION_TOKEN}}")) { throw "Session token placeholder is missing from index.html." }
    $script:AppState.IndexHtml = $index.Replace("{{SESSION_TOKEN}}", $script:AppState.Token)

    $script:AppState.RepoPath = ""
    $script:AppState.SelectedPath = ""
    $script:AppState.LocalScannedAt = ""
    $script:AppState.RemoteFetchedAt = ""
    $script:AppState.LocalStatusSignature = ""
    $script:AppState.RemoteSnapshotCache = $null
    $script:AppState.RemoteSnapshotKey = ""
    Reset-BranchlineQueryCache
    $candidate = $RepoPath
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = Get-SavedFolder }
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        try {
            $safe = Resolve-SafeDirectory $candidate
            $script:AppState.SelectedPath = $safe
            if (Test-GitRepository $safe) {
                $root = Get-GitRepositoryRoot $safe
                $script:AppState.RepoPath = $root
                $script:AppState.SelectedPath = $root
                $script:AppState.StartupMessage = "Repository restored from your last session."
            } else {
                $script:AppState.RepoPath = ""
                $script:AppState.StartupMessage = "Normal folder restored. Make it a Git repository, or clone GitHub here if it is empty."
            }
        }
        catch {
            $script:AppState.RepoPath = ""
            $script:AppState.SelectedPath = ""
            $script:AppState.StartupMessage = $_.Exception.Message
        }
    }
}

function Get-RunningBranchlineAboutOnce {
    param([string]$Url)

    $response = $null
    try {
        $aboutUrl = ([Uri]::new([Uri]$Url, "/api/about")).AbsoluteUri
        $request = [System.Net.HttpWebRequest]::Create($aboutUrl)
        $request.Method = "GET"
        $request.Timeout = 1500
        $request.ReadWriteTimeout = 1500
        $request.AllowAutoRedirect = $false
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { return $false }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $body = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
        $about = $body | ConvertFrom-Json
        if ([string]$about.appId -cne "branchline" -or [string]::IsNullOrWhiteSpace([string]$about.installId)) { return $null }
        return $about
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Get-RunningBranchlineAbout {
    param([string]$Url)
    for ($attempt = 0; $attempt -lt 3; $attempt += 1) {
        $about = Get-RunningBranchlineAboutOnce $Url
        if ($null -ne $about) { return $about }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 120 }
    }
    return $null
}

function Test-RunningBranchlineEndpoint {
    param([string]$Url)
    return ($null -ne (Get-RunningBranchlineAbout $Url))
}

function Start-GitControlPanel {
    param(
        [string]$RepoPath = "",
        [ValidateRange(1024, 65535)][int]$Port = 4848,
        [Parameter(Mandatory = $true)][string]$WebRoot,
        [string]$ProjectRoot = "",
        [string]$InstallId = "",
        [switch]$NoBrowser,
        [switch]$AllowLocalTestRemote
    )

    Initialize-GitControlState -RepoPath $RepoPath -Port $Port -WebRoot $WebRoot -ProjectRoot $ProjectRoot -InstallId $InstallId -AllowLocalTestRemote:$AllowLocalTestRemote
    $listener = $null
    $url = ""
    $selectedPort = 0
    for ($candidatePort = $Port; $candidatePort -le [Math]::Min(65535, $Port + 20); $candidatePort += 1) {
        $candidateUrl = "http://127.0.0.1:$candidatePort/"
        $candidateListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $candidatePort)
        try {
            $candidateListener.Start()
            $listener = $candidateListener
            $selectedPort = $candidatePort
            $url = $candidateUrl
            break
        }
        catch {
            $candidateListener.Stop()
            $about = Get-RunningBranchlineAbout $candidateUrl
            if (Test-MatchingBranchlineInstance $about) {
                Write-Host "Branchline is already running at $candidateUrl" -ForegroundColor Yellow
                Write-Host "Reusing the verified installation and version."
                if (-not $NoBrowser) {
                    try { Start-Process $candidateUrl | Out-Null }
                    catch { Write-Warning "Open $candidateUrl in your browser." }
                }
                return
            }
        }
    }
    if ($null -eq $listener) { throw "Branchline could not find a free local port between $Port and $([Math]::Min(65535, $Port + 20))." }
    $script:AppState.Port = $selectedPort
    $activeStatePath = Join-Path $script:AppState.RuntimePath "active.json"
    try {
        Write-BranchlineActiveRuntimeState -Path $activeStatePath -Port $selectedPort
        $script:AppState.RuntimeStateCheckedAt = [DateTime]::UtcNow

        Write-Host ""
        Write-Host "  Branchline Git Workbench" -ForegroundColor Cyan
        Write-Host "  Local-only server: $url"
        Write-Host "  Repository: $($script:AppState.RepoPath)"
        Write-Host "  Stop safely with Ctrl+C"
        Write-Host ""

        if (-not $NoBrowser) {
            try { Start-Process $url | Out-Null }
            catch { Write-Warning "Open $url in your browser." }
        }

        while ($true) {
            # AcceptTcpClient() blocks inside .NET and can prevent Windows
            # PowerShell from observing Ctrl+C. Polling Pending() keeps the
            # console interruptible while remaining effectively idle.
            while (-not $listener.Pending()) {
                if (([DateTime]::UtcNow - [DateTime]$script:AppState.RuntimeStateCheckedAt).TotalSeconds -ge 5) {
                    try { Ensure-BranchlineActiveRuntimeState -Path $activeStatePath -Port $selectedPort }
                    catch { Write-Verbose "The runtime marker could not be refreshed: $($_.Exception.Message)" }
                    $script:AppState.RuntimeStateCheckedAt = [DateTime]::UtcNow
                }
                # Keep Ctrl+C observable without making every browser request
                # wait behind a coarse 100 ms accept interval. Twenty-five
                # milliseconds remains effectively idle while making local UI
                # actions and incremental refreshes feel immediate.
                Start-Sleep -Milliseconds 25
            }
            $client = $listener.AcceptTcpClient()
            try {
                $client.NoDelay = $true
                $client.ReceiveTimeout = 10000
                $client.SendTimeout = 10000
                $stream = $client.GetStream()
                try {
                    $request = Read-HttpRequest $stream
                    $response = Handle-HttpRequest $request
                }
                catch {
                    $response = New-HttpResponse -Status 400 -Body (ConvertTo-JsonText @{ ok = $false; message = "Invalid request." })
                }
                $stream.Write($response.Header, 0, $response.Header.Length)
                if ($response.Body.Length -gt 0) { $stream.Write($response.Body, 0, $response.Body.Length) }
                $stream.Flush()
            }
            catch [System.IO.IOException] {
                # Browsers routinely cancel an in-flight localhost response while
                # reloading or closing a tab. That is harmless and should not alarm
                # the user with a generic warning.
                Write-Verbose "The browser closed a local connection before the response finished."
            }
            catch [System.Net.Sockets.SocketException] {
                Write-Verbose "The browser closed a local socket."
            }
            catch {
                Write-Warning "A local request could not be completed: $($_.Exception.Message)"
            }
            finally {
                $client.Close()
            }
        }
    }
    finally {
        if ($null -ne $listener) { $listener.Stop() }
        try {
            if (Test-Path -LiteralPath $activeStatePath -PathType Leaf) {
                $active = Get-Content -Raw -LiteralPath $activeStatePath -Encoding UTF8 | ConvertFrom-Json
                if ([int]$active.processId -eq $PID -and [string]$active.installId -ceq $script:AppState.InstallId) { Remove-Item -LiteralPath $activeStatePath -Force }
            }
        }
        catch { }
    }
}

Export-ModuleMember -Function @(
    "Start-GitControlPanel",
    "Initialize-GitControlState",
    "ConvertTo-GitHubRemoteValue",
    "ConvertTo-WindowsCommandLineArgument",
    "Get-AppSummary",
    "Invoke-AppAction",
    "New-SessionToken",
    "New-HttpResponse"
)
