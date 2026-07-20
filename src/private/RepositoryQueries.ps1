function Get-PayloadInteger {
    param([object]$Payload, [string]$Name, [int]$Default, [int]$Minimum, [int]$Maximum)
    $property = if ($null -ne $Payload) { $Payload.PSObject.Properties[$Name] } else { $null }
    $value = $Default
    if ($null -ne $property -and $null -ne $property.Value) {
        $parsed = 0
        if ([int]::TryParse([string]$property.Value, [ref]$parsed)) { $value = $parsed }
    }
    return [Math]::Max($Minimum, [Math]::Min($Maximum, $value))
}

function Assert-SafeRepositoryPath {
    param([string]$RepoPath, [string]$Path, [switch]$MayBeMissing)
    if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)) { throw "Choose a repository file first." }
    $normalized = $Path.Replace('\', '/').TrimStart('/')
    if ($normalized -eq ".git" -or $normalized.StartsWith(".git/") -or $normalized -match '(^|/)\.\.(/|$)' -or $normalized.Contains(":")) { throw "That file path is not allowed." }
    $root = [System.IO.Path]::GetFullPath($RepoPath).TrimEnd('\')
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $normalized.Replace('/', '\')))
    if (-not $candidate.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw "That file path leaves the selected repository." }
    if (-not $MayBeMissing -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "That repository file does not exist in the working copy." }
    $cursor = if (Test-Path -LiteralPath $candidate) { $candidate } else { Split-Path -Parent $candidate }
    while (-not [string]::IsNullOrWhiteSpace($cursor) -and $cursor.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Branchline will not preview files through a junction or symbolic link." }
        }
        if ($cursor.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $next = Split-Path -Parent $cursor
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    return [pscustomobject]@{ path = $normalized; fullPath = $candidate }
}

function Test-PreviewBinaryText {
    param([string]$Text)
    if ($Text.IndexOf([char]0) -ge 0) { return $true }
    $sampleLength = [Math]::Min(8192, $Text.Length)
    if ($sampleLength -eq 0) { return $false }
    $controls = 0
    for ($index = 0; $index -lt $sampleLength; $index += 1) {
        $code = [int]$Text[$index]
        if ($code -lt 32 -and $code -notin @(9, 10, 13)) { $controls += 1 }
    }
    return (($controls / [double]$sampleLength) -gt 0.02)
}

function Get-RepositoryFilePageLegacy {
    param([string]$RepoPath, [string]$Side, [string]$Query, [int]$Offset, [int]$Limit)
    $normalizedSide = if ($Side -ceq "github") { "github" } else { "local" }
    $paths = @()
    $statusMap = @{}
    $trackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $branch = ""

    if ($normalizedSide -eq "local") {
        $working = Get-WorkingTreeState $RepoPath
        if (-not $working.ok) { throw "Branchline could not list local files because repository status failed.`n$($working.error)" }
        foreach ($file in @($working.files)) { $statusMap[[string]$file.path] = $file }
        $tracked = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-files", "--cached", "-z") -DisplayCommand "list tracked files" -TimeoutSeconds 30
        if (-not $tracked.ok) { throw "Branchline could not list tracked files.`n$($tracked.output)" }
        foreach ($value in @(Get-NulItems $tracked.raw)) { [void]$trackedSet.Add(([string]$value).Replace('\', '/')) }
        $all = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-files", "--cached", "--others", "--exclude-standard", "-z") -DisplayCommand "list local repository files" -TimeoutSeconds 30
        if (-not $all.ok) { throw "Branchline could not list local repository files.`n$($all.output)" }
        $paths = @(Get-NulItems $all.raw | ForEach-Object { ([string]$_).Replace('\', '/') })
        foreach ($file in @($working.files)) {
            if ($paths -cnotcontains [string]$file.path) { $paths += [string]$file.path }
        }
        $branch = Get-CurrentBranch $RepoPath
    }
    else {
        [void](Assert-OriginAllowed $RepoPath)
        $branch = Get-CurrentBranch $RepoPath
        if ([string]::IsNullOrWhiteSpace($branch)) { throw "Create a named local branch before browsing its GitHub counterpart." }
        $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch $branch
        $remoteBranch = if ($tracking.matchingRemoteExists) { [string]$tracking.remoteBranch } else { [string]$tracking.remoteDefaultBranch }
        if ([string]::IsNullOrWhiteSpace($remoteBranch)) { throw "No fetched GitHub branch is available to browse." }
        $branch = $remoteBranch
        $remoteRef = "refs/remotes/origin/$remoteBranch"
        $tree = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-tree", "-r", "--name-only", "-z", $remoteRef) -DisplayCommand "list fetched GitHub files" -TimeoutSeconds 30
        if (-not $tree.ok) { throw "Branchline could not list the fetched GitHub files.`n$($tree.output)" }
        $paths = @(Get-NulItems $tree.raw | ForEach-Object { ([string]$_).Replace('\', '/') })
        $snapshot = Get-RemoteSnapshot -RepoPath $RepoPath -Tracking $tracking
        foreach ($incoming in @($snapshot.incomingFiles)) { $statusMap[[string]$incoming] = [pscustomobject]@{ state = "incoming"; status = ""; tracked = $true } }
    }

    $queryValue = if ($null -eq $Query) { "" } else { $Query.Trim() }
    $unique = @($paths | Sort-Object -Unique | Where-Object { [string]::IsNullOrWhiteSpace($queryValue) -or ([string]$_).IndexOf($queryValue, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
    $total = $unique.Count
    $page = @($unique | Select-Object -Skip $Offset -First $Limit | ForEach-Object {
        $path = [string]$_
        $status = if ($statusMap.ContainsKey($path)) { $statusMap[$path] } else { $null }
        [pscustomobject]@{
            path = $path
            tracked = if ($normalizedSide -eq "github") { $true } else { $trackedSet.Contains($path) }
            status = if ($null -ne $status) { [string]$status.status } else { "" }
            state = if ($null -ne $status) { [string]$status.state } elseif ($normalizedSide -eq "github") { "remote" } else { "unchanged" }
        }
    })
    return [pscustomobject]@{
        side = $normalizedSide
        branch = $branch
        query = $queryValue
        offset = $Offset
        limit = $Limit
        total = $total
        nextOffset = if (($Offset + $page.Count) -lt $total) { $Offset + $page.Count } else { -1 }
        items = $page
    }
}

function Get-RepositoryFilePage {
    param([string]$RepoPath, [string]$Side, [string]$Query, [int]$Offset, [int]$Limit)
    $normalizedSide = if ($Side -ceq "github") { "github" } else { "local" }
    $working = Get-WorkingTreeState $RepoPath
    if (-not $working.ok) { throw "Branchline could not list files because repository status failed.`n$($working.error)" }
    $revisions = Get-RepositoryRevisions -RepoPath $RepoPath -WorkingState $working
    $index = $null

    if ($normalizedSide -eq "local") {
        $indexKey = "$($revisions.repository)|local|$($working.signature)|$($working.headCommit)"
        $index = Get-BranchlineCacheEntry -Name "local-files" -Key $indexKey
        if ($null -eq $index) {
            $statusMap = @{}
            $untrackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($file in @($working.files)) {
                $path = [string]$file.path
                $statusMap[$path] = $file
                if (-not [bool]$file.tracked) { [void]$untrackedSet.Add($path) }
            }
            # The porcelain-v2 status scan already enumerated every untracked
            # path. Asking ls-files for --others would walk the whole working
            # tree a second time, which is especially expensive on Windows and
            # under real-time antivirus scanning. Read the index only, then add
            # the untracked paths from that authoritative status snapshot.
            $listing = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-files", "--cached", "-z") -DisplayCommand "index tracked repository files" -TimeoutSeconds 30 -ReadOnly
            if (-not $listing.ok) { throw "Branchline could not list local repository files.`n$($listing.output)" }
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $pathsList = New-Object System.Collections.Generic.List[string]
            [int64]$estimatedBytes = 4096
            foreach ($recordValue in @(Get-NulItems $listing.raw)) {
                $path = ([string]$recordValue).Replace('\', '/')
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                if (-not $seen.Add($path)) { continue }
                $pathsList.Add($path)
                $estimatedBytes += ([int64]$path.Length * 2 + 48)
            }
            foreach ($file in @($working.files)) {
                $path = [string]$file.path
                if ($seen.Add($path)) {
                    $pathsList.Add($path)
                    $estimatedBytes += ([int64]$path.Length * 2 + 48)
                    if (-not [bool]$file.tracked) { [void]$untrackedSet.Add($path) }
                }
            }
            $paths = $pathsList.ToArray()
            $index = [pscustomobject]@{ side = "local"; branch = [string]$working.branch; revision = $indexKey; total = $paths.Count; paths = $paths; statusMap = $statusMap; untracked = $untrackedSet }
            Set-BranchlineCacheEntry -Name "local-files" -Key $indexKey -Value $index -SizeBytes $estimatedBytes | Out-Null
        }
    }
    else {
        $originKey = "$($revisions.repository)|$($revisions.config)"
        $origin = Get-CachedRepositoryValue -Name "origin" -Key $originKey -Factory { Get-OriginInfo $RepoPath } -SizeBytes 8192
        if (-not $origin.configured) { throw "Configure a GitHub origin first." }
        if (-not $origin.valid) { throw "The origin is not an approved GitHub URL." }
        $localBranch = [string]$working.branch
        if ([string]::IsNullOrWhiteSpace($localBranch)) { throw "Create a named local branch before browsing its GitHub counterpart." }
        $branchesKey = "$($revisions.repository)|$($revisions.localRefs)|$($revisions.head)"
        $branches = @(Get-CachedRepositoryValue -Name "branches" -Key $branchesKey -Factory { @(Get-Branches $RepoPath) } -SizeBytes 65536)
        $trackingKey = "$($revisions.repository)|$($revisions.head)|$($revisions.config)|$($revisions.localRefs)|$($revisions.remoteRefs)"
        $tracking = Get-CachedRepositoryValue -Name "tracking" -Key $trackingKey -Factory { Get-TrackingStatus -RepoPath $RepoPath -Branch $localBranch -LocalBranches $branches } -SizeBytes 32768
        $remoteBranch = if ($tracking.matchingRemoteExists) { [string]$tracking.remoteBranch } else { [string]$tracking.remoteDefaultBranch }
        if ([string]::IsNullOrWhiteSpace($remoteBranch)) { throw "No fetched GitHub branch is available to browse." }
        $remoteRef = "refs/remotes/origin/$remoteBranch"
        $object = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-parse", "--verify", $remoteRef) -DisplayCommand "identify fetched GitHub files" -TimeoutSeconds 10 -ReadOnly
        if (-not $object.ok) { throw "The fetched GitHub branch is no longer available." }
        $indexKey = "$($revisions.repository)|github|$remoteBranch|$($object.raw.Trim())|$($working.headCommit)"
        $index = Get-BranchlineCacheEntry -Name "remote-files" -Key $indexKey
        if ($null -eq $index) {
            $tree = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "ls-tree", "-r", "--name-only", "-z", $remoteRef) -DisplayCommand "index fetched GitHub files" -TimeoutSeconds 30 -ReadOnly
            if (-not $tree.ok) { throw "Branchline could not list the fetched GitHub files.`n$($tree.output)" }
            $snapshot = Get-RemoteSnapshot -RepoPath $RepoPath -Tracking $tracking -HeadCommit ([string]$working.headCommit)
            $incomingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($incoming in @($snapshot.incomingFiles)) { [void]$incomingSet.Add([string]$incoming) }
            $paths = @(Get-NulItems $tree.raw | ForEach-Object { ([string]$_).Replace('\', '/') })
            $estimatedBytes = [int64](4096 + (($paths | ForEach-Object { ([string]$_).Length * 2 + 40 } | Measure-Object -Sum).Sum))
            $index = [pscustomobject]@{ side = "github"; branch = $remoteBranch; revision = $indexKey; total = $paths.Count; paths = $paths; incoming = $incomingSet }
            Set-BranchlineCacheEntry -Name "remote-files" -Key $indexKey -Value $index -SizeBytes $estimatedBytes | Out-Null
        }
    }

    $queryValue = if ($null -eq $Query) { "" } else { $Query.Trim() }
    if ([string]::IsNullOrWhiteSpace($queryValue)) {
        $total = [int]$index.total
        if ($Offset -ge $total) { $pagePaths = @() }
        else {
            $last = [Math]::Min($total - 1, $Offset + $Limit - 1)
            $pagePaths = @($index.paths[$Offset..$last])
        }
    }
    else {
        $filtered = @($index.paths | Where-Object { ([string]$_).IndexOf($queryValue, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        $total = $filtered.Count
        $pagePaths = @($filtered | Select-Object -Skip $Offset -First $Limit)
    }
    $page = @($pagePaths | ForEach-Object {
        $path = [string]$_
        if ($normalizedSide -eq "github") {
            [pscustomobject]@{ path = $path; tracked = $true; status = ""; state = if ($index.incoming.Contains($path)) { "incoming" } else { "remote" } }
        }
        else {
            $status = if ($index.statusMap.ContainsKey($path)) { $index.statusMap[$path] } else { $null }
            [pscustomobject]@{
                path = $path; tracked = -not $index.untracked.Contains($path)
                status = if ($null -ne $status) { [string]$status.status } else { "" }
                state = if ($null -ne $status) { [string]$status.state } else { "unchanged" }
            }
        }
    })
    return [pscustomobject]@{
        side = $normalizedSide; branch = [string]$index.branch; revision = [string]$index.revision; query = $queryValue; offset = $Offset; limit = $Limit; total = $total
        nextOffset = if (($Offset + $page.Count) -lt $total) { $Offset + $page.Count } else { -1 }; items = $page
    }
}

function Get-RepositoryFilePreview {
    param([string]$RepoPath, [string]$Side, [string]$Path)
    $normalizedSide = if ($Side -ceq "github") { "github" } else { "local" }
    $safe = Assert-SafeRepositoryPath -RepoPath $RepoPath -Path $Path -MayBeMissing:($normalizedSide -eq "github")
    $content = ""
    $diff = ""
    $kind = "text"
    [int64]$byteLength = 0
    $branch = ""

    if ($normalizedSide -eq "local") {
        $validated = Resolve-RepositoryFile -RepoPath $RepoPath -Path $safe.path
        $branch = Get-CurrentBranch $RepoPath
        if (Test-Path -LiteralPath $safe.fullPath -PathType Leaf) {
            $item = Get-Item -LiteralPath $safe.fullPath -Force
            $byteLength = [int64]$item.Length
            if ($byteLength -gt $script:MaxPreviewBytes) { $kind = "too-large" }
            else {
                $bytes = [System.IO.File]::ReadAllBytes($safe.fullPath)
                try { $content = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
                catch { $kind = "binary" }
                if ($kind -eq "text" -and (Test-PreviewBinaryText $content)) { $kind = "binary"; $content = "" }
            }
        }
        else { $kind = "deleted" }
        $staged = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--unified=3", "--staged", "--", $validated) -DisplayCommand "staged diff for $validated" -TimeoutSeconds 30 -ReadOnly
        $unstaged = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--unified=3", "--", $validated) -DisplayCommand "working diff for $validated" -TimeoutSeconds 30 -ReadOnly
        if (-not $staged.ok -or -not $unstaged.ok) { throw "Branchline could not generate the local diff." }
        $diff = Limit-Text (Join-CommandOutput @("STAGED DIFF", $(if ([string]::IsNullOrWhiteSpace($staged.output)) { "No staged difference." } else { $staged.output }), "WORKING TREE DIFF", $(if ([string]::IsNullOrWhiteSpace($unstaged.output)) { "No unstaged difference." } else { $unstaged.output })))
    }
    else {
        [void](Assert-OriginAllowed $RepoPath)
        $localBranch = Get-CurrentBranch $RepoPath
        if ([string]::IsNullOrWhiteSpace($localBranch)) { throw "Create a named branch before previewing GitHub files." }
        $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch $localBranch
        $branch = if ($tracking.matchingRemoteExists) { [string]$tracking.remoteBranch } else { [string]$tracking.remoteDefaultBranch }
        if ([string]::IsNullOrWhiteSpace($branch)) { throw "No fetched GitHub branch is available." }
        $remoteRef = "refs/remotes/origin/$branch"
        $entry = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("-c", "core.quotepath=false", "--literal-pathspecs", "ls-tree", "-z", $remoteRef, "--", $safe.path) -DisplayCommand "locate fetched GitHub file" -TimeoutSeconds 20 -ReadOnly
        if (-not $entry.ok -or [string]::IsNullOrWhiteSpace($entry.raw)) { throw "That file does not exist in the fetched GitHub snapshot." }
        $record = ([string]$entry.raw).Trim([char]0)
        if ($record -notmatch '^[0-9]+\s+blob\s+([0-9a-f]{40,64})\t(.+)$' -or $Matches[2].Replace('\', '/') -cne $safe.path) { throw "The fetched GitHub entry is not a regular file." }
        $objectId = $Matches[1]
        $size = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("cat-file", "-s", $objectId) -DisplayCommand "measure fetched GitHub file" -TimeoutSeconds 10 -ReadOnly
        if (-not $size.ok -or -not [int64]::TryParse($size.raw.Trim(), [ref]$byteLength)) { throw "Branchline could not measure the fetched GitHub file." }
        if ($byteLength -gt $script:MaxPreviewBytes) { $kind = "too-large" }
        else {
            $blob = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("cat-file", "blob", $objectId) -DisplayCommand "read fetched GitHub file" -TimeoutSeconds 30 -ReadOnly
            if (-not $blob.ok) { throw "Branchline could not read the fetched GitHub file." }
            $content = [string]$blob.raw
            if (Test-PreviewBinaryText $content) { $kind = "binary"; $content = "" }
        }
        $head = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("rev-parse", "--verify", "HEAD") -DisplayCommand "check local comparison base" -TimeoutSeconds 10 -ReadOnly
        if ($head.ok) {
            $difference = Invoke-GitCommand -WorkingDirectory $RepoPath -Arguments @("--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--unified=3", "HEAD", $remoteRef, "--", $safe.path) -DisplayCommand "compare local and fetched GitHub file" -TimeoutSeconds 30 -ReadOnly
            if ($difference.ok) { $diff = if ([string]::IsNullOrWhiteSpace($difference.output)) { "No net difference from local HEAD." } else { $difference.output } }
        }
    }

    return [pscustomobject]@{
        side = $normalizedSide
        path = $safe.path
        branch = $branch
        kind = $kind
        byteLength = $byteLength
        content = if ($kind -eq "text") { Limit-Text $content $script:MaxPreviewBytes } else { "" }
        diff = Limit-Text $diff
        maxPreviewBytes = $script:MaxPreviewBytes
    }
}
