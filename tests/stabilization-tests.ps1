[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:Passed = 0
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot "src\GitControlPanel.psm1"
$webRoot = Join-Path $projectRoot "web"
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $temporaryBase ("Branchline-stabilization-" + [Guid]::NewGuid().ToString("N"))
$originalLocalAppData = $env:LOCALAPPDATA
$originalGlobalConfig = $env:GIT_CONFIG_GLOBAL

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:Passed += 1
    Write-Host "  PASS  $Message" -ForegroundColor Green
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if ([string]$Expected -cne [string]$Actual) { throw "FAILED: $Message`nExpected: $Expected`nActual:   $Actual" }
    $script:Passed += 1
    Write-Host "  PASS  $Message" -ForegroundColor Green
}

function Invoke-TestGit {
    param([string]$WorkingDirectory, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git.exe -C $WorkingDirectory @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "Fixture Git failed: git -C $WorkingDirectory $($Arguments -join ' ')`n$($output -join "`n")" }
    return ($output -join "`n")
}

function New-TestRepository {
    param([string]$Name)
    $repository = Join-Path $testRoot $Name
    [System.IO.Directory]::CreateDirectory($repository) | Out-Null
    [void](Invoke-TestGit $repository @("init", "-b", "main"))
    [void](Invoke-TestGit $repository @("config", "user.name", "Branchline Stabilization Test"))
    [void](Invoke-TestGit $repository @("config", "user.email", "stabilization@example.invalid"))
    [System.IO.File]::WriteAllText((Join-Path $repository "README.md"), "# Stabilization fixture`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-TestGit $repository @("add", "README.md"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Initial fixture"))
    return $repository
}

try {
    Write-Host "Branchline 0.9.0-beta stabilization tests" -ForegroundColor Cyan
    [System.IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $env:LOCALAPPDATA = Join-Path $testRoot "state"
    Import-Module $modulePath -Force

    $repository = New-TestRepository "working repository"
    $remote = Join-Path $testRoot "origin.git"
    [System.IO.Directory]::CreateDirectory($remote) | Out-Null
    [void](Invoke-TestGit $remote @("init", "--bare"))
    [void](Invoke-TestGit $remote @("symbolic-ref", "HEAD", "refs/heads/main"))
    [void](Invoke-TestGit $repository @("remote", "add", "origin", $remote))
    [void](Invoke-TestGit $repository @("push", "-u", "origin", "main"))
    Initialize-GitControlState -RepoPath $repository -Port 4848 -WebRoot $webRoot -AllowLocalTestRemote

    Write-Host "`nStructured state and identity"
    $summary = Get-AppSummary
    Assert-True ($summary.stateOk -and $summary.headState -eq "branch") "reports an explicit healthy attached HEAD"
    Assert-True ($null -ne $summary.changedFiles -and @($summary.changedFiles).Count -eq 0) "keeps an empty working tree as an explicit empty array"
    $unknown = Invoke-AppAction ([pscustomobject]@{ action = "removedLegacyAction" })
    Assert-True (-not $unknown.ok -and $null -ne $unknown.steps -and -not [string]::IsNullOrWhiteSpace($unknown.phase)) "returns structured fields even for rejected actions"

    $identityRepository = New-TestRepository "identity repository"
    [void](Invoke-TestGit $identityRepository @("config", "--local", "--unset-all", "user.name"))
    [void](Invoke-TestGit $identityRepository @("config", "--local", "--unset-all", "user.email"))
    $globalConfig = Join-Path $testRoot "isolated-global.gitconfig"
    [System.IO.File]::WriteAllText($globalConfig, "[user]`n`tname = Inherited User`n`temail = inherited@example.invalid`n", (New-Object System.Text.UTF8Encoding($false)))
    $env:GIT_CONFIG_GLOBAL = $globalConfig
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $identityRepository }))
    $identity = (Get-AppSummary).identity
    Assert-True (-not $identity.configured -and $identity.inheritedAvailable -and $identity.source -eq "global") "distinguishes inherited global identity from repository-local identity"
    $env:GIT_CONFIG_GLOBAL = $originalGlobalConfig

    Write-Host "`nDetached HEAD and tracking workflows"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository }))
    [void](Invoke-TestGit $repository @("checkout", "--detach", "HEAD"))
    $detached = Get-AppSummary
    Assert-True ($detached.headState -eq "detached" -and $detached.tracking.relationship -eq "detached") "detects detached HEAD instead of presenting an empty repository"
    $rescued = Invoke-AppAction ([pscustomobject]@{ action = "createBranch"; branch = "rescue/detached" })
    Assert-True ($rescued.ok -and (Get-AppSummary).branch -eq "rescue/detached") "creates a named branch at a detached commit"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "switchBranch"; branch = "main" }))

    $peer = Join-Path $testRoot "remote peer"
    [void](Invoke-TestGit $testRoot @("clone", "--quiet", $remote, $peer))
    [void](Invoke-TestGit $peer @("config", "user.name", "Remote Test"))
    [void](Invoke-TestGit $peer @("config", "user.email", "remote@example.invalid"))
    [void](Invoke-TestGit $peer @("switch", "-c", "remote-only"))
    [System.IO.File]::WriteAllText((Join-Path $peer "REMOTE-ONLY.md"), "remote branch`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-TestGit $peer @("add", "REMOTE-ONLY.md"))
    [void](Invoke-TestGit $peer @("commit", "-m", "Remote-only branch"))
    [void](Invoke-TestGit $peer @("push", "-u", "origin", "remote-only"))
    $fetched = Invoke-AppAction ([pscustomobject]@{ action = "fetch" })
    Assert-True ($fetched.ok -and -not [string]::IsNullOrWhiteSpace((Get-AppSummary).remoteFetchedAt)) "records a distinct GitHub fetch timestamp"
    Assert-Equal "refs/remotes/origin/main" (Invoke-TestGit $repository @("symbolic-ref", "refs/remotes/origin/HEAD")) "refreshes origin/HEAD after fetch"
    $checkedOutRemote = Invoke-AppAction ([pscustomobject]@{ action = "checkoutRemoteBranch"; branch = "remote-only"; confirm = "TRACK_REMOTE:remote-only" })
    Assert-True ($checkedOutRemote.ok -and (Get-AppSummary).branch -eq "remote-only" -and (Test-Path -LiteralPath (Join-Path $repository "REMOTE-ONLY.md"))) "checks out and tracks a remote-only branch"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "switchBranch"; branch = "main" }))
    [void](Invoke-TestGit $repository @("branch", "--set-upstream-to=origin/remote-only", "main"))
    Assert-Equal "upstream-mismatch" (Get-AppSummary).tracking.relationship "detects a mismatched upstream"
    $repaired = Invoke-AppAction ([pscustomobject]@{ action = "repairUpstream"; confirm = "REPAIR_UPSTREAM:main" })
    Assert-True ($repaired.ok -and (Get-AppSummary).tracking.upstream -eq "origin/main") "repairs tracking only after confirmation"

    $newBranch = Invoke-AppAction ([pscustomobject]@{ action = "createBranch"; branch = "feature/new-github-branch" })
    Assert-True $newBranch.ok "creates a local branch before separate publication"
    [System.IO.File]::WriteAllText((Join-Path $repository "NEW-BRANCH.md"), "new branch`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-TestGit $repository @("add", "NEW-BRANCH.md"))
    [void](Invoke-TestGit $repository @("commit", "-m", "New branch work"))
    $publishedNew = Invoke-AppAction ([pscustomobject]@{ action = "publishNewBranch"; confirm = "PUBLISH_NEW_BRANCH:feature/new-github-branch" })
    Assert-True ($publishedNew.ok -and (Invoke-TestGit $remote @("show-ref", "--verify", "refs/heads/feature/new-github-branch")).Length -gt 0) "publishes a missing GitHub branch through its distinct action"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "switchBranch"; branch = "main" }))

    Write-Host "`nRead-only file browsers"
    [System.IO.File]::WriteAllText((Join-Path $repository "unicodé file.txt"), "hello ünicode`nsecond line`n", (New-Object System.Text.UTF8Encoding($false)))
    $localPage = Invoke-AppAction ([pscustomobject]@{ action = "listFiles"; side = "local"; query = "unicodé"; offset = 0; limit = 20 })
    Assert-True ($localPage.ok -and $localPage.page.total -eq 1 -and $localPage.page.items[0].path -eq "unicodé file.txt") "searches the lazy local file index with Unicode paths"
    $textPreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "local"; file = "unicodé file.txt" })
    Assert-True ($textPreview.ok -and $textPreview.preview.kind -eq "text" -and $textPreview.preview.content.Contains("ünicode")) "previews an untracked UTF-8 text file safely"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = "unicodé file.txt" }))
    $stagedPreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "local"; file = "unicodé file.txt" })
    Assert-True ($stagedPreview.preview.diff.Contains("STAGED DIFF") -and $stagedPreview.preview.diff.Contains("+hello")) "shows staged and unstaged differences in the local preview"

    [System.IO.File]::WriteAllBytes((Join-Path $repository "binary.dat"), [byte[]](0, 255, 1, 2, 3))
    $binaryPreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "local"; file = "binary.dat" })
    Assert-Equal "binary" $binaryPreview.preview.kind "classifies binary files without rendering their content"
    $largeBytes = New-Object byte[] 524289
    [System.IO.File]::WriteAllBytes((Join-Path $repository "large.txt"), $largeBytes)
    $largePreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "local"; file = "large.txt" })
    Assert-True ($largePreview.preview.kind -eq "too-large" -and $largePreview.preview.byteLength -eq 524289) "caps file previews at 512 KiB and returns metadata"
    $traversalPreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "local"; file = "../outside.txt" })
    Assert-True (-not $traversalPreview.ok) "rejects preview path traversal"
    $junctionTarget = Join-Path $testRoot "junction target"
    [System.IO.Directory]::CreateDirectory($junctionTarget) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $junctionTarget "escape.txt"), "outside", (New-Object System.Text.UTF8Encoding($false)))
    $junctionPath = Join-Path $repository "linked"
    try {
        [void](New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget -ErrorAction Stop)
        $junctionPreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "local"; file = "linked/escape.txt" })
        Assert-True (-not $junctionPreview.ok -and $junctionPreview.output.Contains("junction")) "blocks repository previews through a junction"
    }
    catch { Write-Host "  SKIP  junction creation is unavailable on this Windows host" -ForegroundColor Yellow }
    $remotePreview = Invoke-AppAction ([pscustomobject]@{ action = "previewFile"; side = "github"; file = "README.md" })
    Assert-True ($remotePreview.ok -and $remotePreview.preview.kind -eq "text" -and $remotePreview.preview.content.Contains("Stabilization")) "previews the last fetched remote blob rather than a live network file"

    Write-Host "`nFail-closed and recovery behavior"
    [void](Invoke-TestGit $repository @("reset", "--hard", "HEAD"))
    [void](Invoke-TestGit $repository @("clean", "-fd"))
    $gitDirectory = (Invoke-TestGit $repository @("rev-parse", "--git-dir")).Trim()
    if (-not [System.IO.Path]::IsPathRooted($gitDirectory)) { $gitDirectory = Join-Path $repository $gitDirectory }
    $indexPath = Join-Path $gitDirectory "index"
    $savedIndex = [System.IO.File]::ReadAllBytes($indexPath)
    [System.IO.File]::WriteAllText($indexPath, "corrupt-index", (New-Object System.Text.UTF8Encoding($false)))
    $corruptSummary = Get-AppSummary
    Assert-True (-not $corruptSummary.stateOk -and @($corruptSummary.changedFiles).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($corruptSummary.stateError)) "reports a corrupt index explicitly without inventing a clean state"
    $headBeforeBlockedAction = Invoke-TestGit $repository @("rev-parse", "HEAD")
    $blockedMutation = Invoke-AppAction ([pscustomobject]@{ action = "createBranch"; branch = "must-not-exist" })
    Assert-True (-not $blockedMutation.ok -and -not (Test-Path -LiteralPath (Join-Path $gitDirectory "refs\heads\must-not-exist"))) "blocks every mutating action when status cannot be read"
    [System.IO.File]::WriteAllBytes($indexPath, $savedIndex)
    Assert-Equal $headBeforeBlockedAction (Invoke-TestGit $repository @("rev-parse", "HEAD")) "preserves HEAD while a corrupt index blocks mutation"

    $targetCommit = Invoke-TestGit $repository @("rev-parse", "HEAD")
    $resetOne = Invoke-AppAction ([pscustomobject]@{ action = "resetToCommit"; commit = $targetCommit; confirm = "RESET:$targetCommit" })
    $resetTwo = Invoke-AppAction ([pscustomobject]@{ action = "resetToCommit"; commit = $targetCommit; confirm = "RESET:$targetCommit" })
    Assert-True ($resetOne.ok -and $resetTwo.ok -and $resetOne.backupRef -cne $resetTwo.backupRef) "creates collision-proof recovery references for repeated resets"
    Assert-True ((Invoke-TestGit $repository @("show-ref", "--verify", $resetOne.backupRef)).Length -gt 0 -and (Invoke-TestGit $repository @("show-ref", "--verify", $resetTwo.backupRef)).Length -gt 0) "keeps every reset recovery reference addressable"

    $normalFolder = Join-Path $testRoot "invalid restore folder"
    $invalidBackup = Join-Path $normalFolder ".branchline-git-backup-20260717-120000"
    [System.IO.Directory]::CreateDirectory($invalidBackup) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $invalidBackup "not-git.txt"), "invalid", (New-Object System.Text.UTF8Encoding($false)))
    $invalidRestore = Invoke-AppAction ([pscustomobject]@{ action = "restoreGitMetadata"; path = $normalFolder; backup = ".branchline-git-backup-20260717-120000"; confirm = "RESTORE_GIT:.branchline-git-backup-20260717-120000" })
    Assert-True (-not $invalidRestore.ok -and (Test-Path -LiteralPath $invalidBackup) -and -not (Test-Path -LiteralPath (Join-Path $normalFolder ".git"))) "rolls invalid Git-metadata restoration back to its backup name"

    Write-Host "`nPartial commit and push failure"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository }))
    [void](Invoke-TestGit $repository @("switch", "main"))
    [System.IO.File]::WriteAllText((Join-Path $repository "partial.txt"), "commit must survive push failure`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = "partial.txt" }))
    $hook = Join-Path $remote "hooks\pre-receive"
    [System.IO.File]::WriteAllText($hook, "#!/bin/sh`necho Branchline injected push rejection >&2`nexit 1`n", (New-Object System.Text.UTF8Encoding($false)))
    $partial = Invoke-AppAction ([pscustomobject]@{ action = "commitStagedPush"; message = "Preserve partial commit"; confirm = "COMMIT_STAGED_PUSH" })
    Assert-True (-not $partial.ok -and $partial.partial -and $partial.commitCreated -and -not $partial.pushSucceeded) "reports commit success followed by push failure as partial success"
    Assert-Equal "Preserve partial commit" (Invoke-TestGit $repository @("log", "-1", "--format=%s")) "preserves the created commit after push failure"
    Assert-True ($partial.recovery.localCommitPreserved -and $partial.recovery.nextAction -eq "fetch") "returns concrete recovery guidance for a failed publish"
    Remove-Item -LiteralPath $hook -Force
    $retried = Invoke-AppAction ([pscustomobject]@{ action = "push" })
    Assert-True ($retried.ok -and $retried.publishedCommits -ge 1 -and $retried.remainingLocalChanges -eq 0) "retries Publish and reports commit and remaining-file counts"

    Write-Host "`n$($script:Passed) stabilization checks passed." -ForegroundColor Cyan
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:GIT_CONFIG_GLOBAL = $originalGlobalConfig
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).Path).TrimEnd('\')
        if ($resolved.StartsWith($temporaryBase + '\Branchline-stabilization-', [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
