[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$passed = 0
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot "src\GitControlPanel.psm1"
$webRoot = Join-Path $projectRoot "web"
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $temporaryBase ("Branchline-state-cache-" + [Guid]::NewGuid().ToString("N"))
$originalLocalAppData = $env:LOCALAPPDATA

function Assert-State {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:passed += 1
    Write-Host "  PASS  $Message" -ForegroundColor Green
}

function Invoke-FixtureGit {
    param([string]$Repository, [string[]]$Arguments, [switch]$AllowFailure)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = & git.exe -C $Repository @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldPreference }
    if (-not $AllowFailure -and $code -ne 0) { throw "Fixture Git failed: git $($Arguments -join ' ')`n$($output -join "`n")" }
    return [pscustomobject]@{ code = $code; output = ($output -join "`n") }
}

function New-FixtureRepository {
    param([string]$Name)
    $repository = Join-Path $testRoot $Name
    [System.IO.Directory]::CreateDirectory($repository) | Out-Null
    [void](Invoke-FixtureGit $repository @("init", "-b", "main"))
    [void](Invoke-FixtureGit $repository @("config", "user.name", "State Cache Test"))
    [void](Invoke-FixtureGit $repository @("config", "user.email", "state-cache@example.invalid"))
    [System.IO.File]::WriteAllText((Join-Path $repository "tracked.txt"), "base`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-FixtureGit $repository @("add", "tracked.txt"))
    [void](Invoke-FixtureGit $repository @("commit", "-m", "Initial state"))
    return $repository
}

try {
    Write-Host "Branchline repository-state and cache parity tests" -ForegroundColor Cyan
    [System.IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $env:LOCALAPPDATA = Join-Path $testRoot "state"
    Import-Module $modulePath -Force

    $repository = New-FixtureRepository "working repository"
    Initialize-GitControlState -RepoPath $repository -Port 4848 -WebRoot $webRoot -ProjectRoot $projectRoot -InstallId ("b" * 32)
    $clean = Get-AppSummary
    Assert-State ($clean.stateOk -and $clean.headState -eq "branch" -and $clean.branch -eq "main" -and @($clean.changedFiles).Count -eq 0) "reads a clean attached branch through porcelain v2"
    Assert-State (-not [string]::IsNullOrWhiteSpace([string]$clean.revisions.repository) -and -not [string]::IsNullOrWhiteSpace([string]$clean.revisions.head)) "returns opaque repository revisions"

    [System.IO.File]::WriteAllText((Join-Path $repository "new file.txt"), "new`n", (New-Object System.Text.UTF8Encoding($false)))
    Start-Sleep -Milliseconds 2100
    $untracked = Get-AppSummary
    Assert-State (@($untracked.changedFiles | Where-Object { $_.path -eq "new file.txt" -and $_.state -eq "untracked" }).Count -eq 1) "classifies an external untracked file"
    $staged = Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = "new file.txt" })
    $stagedSummary = Get-AppSummary
    Assert-State ($staged.ok -and $staged.refreshScope.local -and -not $staged.refreshScope.full) "returns local-only invalidation after staging"
    Assert-State (@($stagedSummary.changedFiles | Where-Object { $_.path -eq "new file.txt" -and $_.state -eq "staged" }).Count -eq 1) "preserves staged state across cached summaries"

    [System.IO.File]::AppendAllText((Join-Path $repository "new file.txt"), "newer`n")
    Start-Sleep -Milliseconds 2100
    $mixed = Get-AppSummary
    Assert-State (@($mixed.changedFiles | Where-Object { $_.path -eq "new file.txt" -and $_.state -eq "mixed" }).Count -eq 1) "classifies staged plus unstaged edits as mixed"
    [void](Invoke-FixtureGit $repository @("reset", "--hard", "HEAD"))

    [void](Invoke-FixtureGit $repository @("mv", "tracked.txt", "renamed.txt"))
    Start-Sleep -Milliseconds 2100
    $renamed = Get-AppSummary
    Assert-State (@($renamed.changedFiles | Where-Object { $_.path -eq "renamed.txt" -and $_.originalPath -eq "tracked.txt" }).Count -eq 1) "parses staged rename records and their original paths"
    [void](Invoke-FixtureGit $repository @("reset", "--hard", "HEAD"))
    Remove-Item -LiteralPath (Join-Path $repository "tracked.txt") -Force
    Start-Sleep -Milliseconds 2100
    $deleted = Get-AppSummary
    Assert-State (@($deleted.changedFiles | Where-Object { $_.path -eq "tracked.txt" -and $_.state -eq "deleted" }).Count -eq 1) "classifies working-tree deletion"
    [void](Invoke-FixtureGit $repository @("reset", "--hard", "HEAD"))

    [void](Invoke-FixtureGit $repository @("config", "user.name", "Externally Updated"))
    $identityChanged = Get-AppSummary
    Assert-State ($identityChanged.identity.name -eq "Externally Updated" -and $identityChanged.revisions.config -cne $clean.revisions.config) "invalidates identity when repository configuration changes externally"
    [void](Invoke-FixtureGit $repository @("branch", "external-branch"))
    $branchChanged = Get-AppSummary
    Assert-State (@($branchChanged.branches | Where-Object { $_.name -eq "external-branch" }).Count -eq 1) "invalidates branch lists when refs change externally"

    $gitDirectory = Join-Path $repository ".git"
    $indexPath = Join-Path $gitDirectory "index"
    $savedIndex = [System.IO.File]::ReadAllBytes($indexPath)
    [System.IO.File]::WriteAllText($indexPath, "corrupt-index", (New-Object System.Text.UTF8Encoding($false)))
    $blocked = Invoke-AppAction ([pscustomobject]@{ action = "createBranch"; branch = "blocked-by-corrupt-index" })
    Assert-State (-not $blocked.ok -and -not (Test-Path -LiteralPath (Join-Path $gitDirectory "refs\heads\blocked-by-corrupt-index"))) "fresh action preflight ignores cached health and blocks a corrupt index"
    [System.IO.File]::WriteAllBytes($indexPath, $savedIndex)

    [void](Invoke-FixtureGit $repository @("checkout", "--detach", "HEAD"))
    Start-Sleep -Milliseconds 2100
    $detached = Get-AppSummary
    Assert-State ($detached.headState -eq "detached" -and -not [string]::IsNullOrWhiteSpace([string]$detached.headCommit)) "parses detached HEAD metadata"

    $unbornRepository = Join-Path $testRoot "unborn repository"
    [System.IO.Directory]::CreateDirectory($unbornRepository) | Out-Null
    [void](Invoke-FixtureGit $unbornRepository @("init", "-b", "main"))
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $unbornRepository }))
    $unborn = Get-AppSummary
    Assert-State ($unborn.stateOk -and $unborn.headState -eq "unborn" -and $unborn.branch -eq "main") "parses an unborn branch without inventing a commit"

    $conflictRepository = New-FixtureRepository "conflict repository"
    [System.IO.File]::WriteAllText((Join-Path $conflictRepository "conflict.txt"), "base`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-FixtureGit $conflictRepository @("add", "conflict.txt"))
    [void](Invoke-FixtureGit $conflictRepository @("commit", "-m", "Conflict base"))
    [void](Invoke-FixtureGit $conflictRepository @("switch", "-c", "side"))
    [System.IO.File]::WriteAllText((Join-Path $conflictRepository "conflict.txt"), "side`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-FixtureGit $conflictRepository @("commit", "-am", "Side change"))
    [void](Invoke-FixtureGit $conflictRepository @("switch", "main"))
    [System.IO.File]::WriteAllText((Join-Path $conflictRepository "conflict.txt"), "main`n", (New-Object System.Text.UTF8Encoding($false)))
    [void](Invoke-FixtureGit $conflictRepository @("commit", "-am", "Main change"))
    [void](Invoke-FixtureGit $conflictRepository @("merge", "side") -AllowFailure)
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $conflictRepository }))
    $conflict = Get-AppSummary
    Assert-State ($conflict.operation -eq "merge" -and @($conflict.changedFiles | Where-Object { $_.state -eq "conflicted" }).Count -eq 1) "parses conflict records and active merge state"

    Write-Host "`n$passed repository-state and cache checks passed." -ForegroundColor Cyan
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).Path).TrimEnd('\')
        if ($resolved.StartsWith($temporaryBase + '\Branchline-state-cache-', [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

# Windows PowerShell 5.1 can otherwise return the exit code from the last
# intentionally failing native Git command even though every assertion passed.
# A thrown PowerShell error never reaches this line, so real failures still
# leave the test process non-zero.
exit 0
