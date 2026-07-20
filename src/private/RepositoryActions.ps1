function New-AppResult {
    param(
        [bool]$Ok,
        [string]$Command,
        [string]$Output,
        [int]$Code = 0,
        [hashtable]$Data = $null,
        [bool]$Partial = $false,
        [string]$Phase = "",
        [object[]]$Steps = @(),
        [hashtable]$Recovery = $null
    )

    $result = [ordered]@{
        ok = $Ok
        code = $Code
        command = $Command
        output = $Output
        partial = $Partial
        phase = $Phase
        steps = @($Steps)
        refreshScope = Get-ActionRefreshScope -Action ([string]$script:AppState.CurrentAction)
    }
    if ($null -ne $Recovery) { $result.recovery = $Recovery }
    if ($null -ne $Data) {
        foreach ($key in $Data.Keys) { $result[$key] = $Data[$key] }
    }
    return [pscustomobject]$result
}

function Get-ActionRefreshScope {
    param([string]$Action)
    $scope = [ordered]@{ local = $false; remote = $false; history = $false; branches = $false; full = $false }
    if ([string]::IsNullOrWhiteSpace($Action) -or $Action -in @("showCommit", "diffFile", "previewFile", "listFiles", "openRepositoryFolder", "githubLogin", "githubResetLogin")) {
        return [pscustomobject]$scope
    }
    if ($Action -in @("selectRepository", "initializeRepository", "cloneRepository", "detachRepository", "restoreGitMetadata", "configureRemote", "adoptRemote")) {
        $scope.full = $true
        return [pscustomobject]$scope
    }
    if ($Action -in @("fetch", "push", "publishNewBranch", "repairUpstream")) { $scope.remote = $true }
    if ($Action -in @("publishNewBranch", "repairUpstream")) { $scope.branches = $true }
    if ($Action -in @("stageAll", "stageFile", "unstageFile", "restoreFile", "setIdentity")) { $scope.local = $true }
    if ($Action -in @("commit", "commitStagedPush", "revertCommit", "restoreFileFromCommit", "resetToCommit")) {
        $scope.local = $true
        $scope.history = $true
    }
    if ($Action -in @("createBranch", "switchBranch", "mergeBranches", "deleteBranch", "checkoutRemoteBranch", "abortOperation")) {
        $scope.local = $true
        $scope.history = $true
        $scope.branches = $true
    }
    if ($Action -in @("pull", "integrateRemote")) {
        $scope.local = $true
        $scope.remote = $true
        $scope.history = $true
        $scope.branches = $true
    }
    return [pscustomobject]$scope
}

function New-ActionStep {
    param([string]$Name, [string]$Status, [string]$Command = "", [string]$Output = "")
    return [pscustomobject][ordered]@{
        name = $Name
        status = $Status
        command = $Command
        output = (Limit-Text $Output 65536)
    }
}

function New-RecoveryId {
    $random = [Guid]::NewGuid().ToString("N").Substring(0, 10)
    return "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$random"
}

function Get-StateIndependentActionNames {
    # Read-only views and setup/recovery operations that cannot rely on a
    # healthy existing index are handled by their own explicit validation.
    return @(
        "selectRepository", "initializeRepository", "cloneRepository",
        "restoreGitMetadata", "listFiles", "previewFile", "showCommit",
        "githubLogin", "githubResetLogin", "openRepositoryFolder"
    )
}

function Assert-RepositoryActionPreflight {
    param([string]$RepoPath, [string]$Action)

    $working = Get-WorkingTreeState -RepoPath $RepoPath -Force
    if (-not $working.ok) {
        throw "Repository status is unavailable, so '$Action' was blocked. Repair the Git repository and refresh before changing anything.`n$($working.error)"
    }

    try {
        # These fresh reads validate HEAD/index metadata, local refs, repository
        # configuration, and—when present—the current branch's remote refs.
        # No cached summary is trusted before a mutation.
        [void](Get-RepositoryRevisions -RepoPath $RepoPath -WorkingState $working)
        $branches = @(Get-Branches $RepoPath)
        $origin = Get-OriginInfo $RepoPath
        if ($origin.valid -and $working.headState -eq "branch" -and -not [string]::IsNullOrWhiteSpace([string]$working.branch)) {
            $tracking = Get-TrackingStatus -RepoPath $RepoPath -Branch ([string]$working.branch) -LocalBranches $branches
            if ([string]$tracking.relationship -eq "error") {
                throw $(if ([string]::IsNullOrWhiteSpace([string]$tracking.error)) { "Git could not compare local and GitHub tracking state." } else { [string]$tracking.error })
            }
        }
    }
    catch {
        throw "Repository branch or tracking state is unavailable, so '$Action' was blocked. Nothing was changed.`n$($_.Exception.Message)"
    }
    return $working
}
