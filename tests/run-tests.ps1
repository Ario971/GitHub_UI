[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:Passed = 0
$script:ServerProcess = $null
$script:OriginalLocalAppData = $env:LOCALAPPDATA
$script:OriginalSkipLegacyMigration = $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot "src\GitControlPanel.psm1"
$webRoot = Join-Path $projectRoot "web"
$runtimeHelperPath = Join-Path $projectRoot "src\private\RuntimeState.ps1"
. $runtimeHelperPath
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $temporaryBase ("Branchline-tests-" + [Guid]::NewGuid().ToString("N"))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:Passed += 1
    Write-Host "  PASS  $Message" -ForegroundColor Green
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if ([string]$Expected -cne [string]$Actual) {
        throw "FAILED: $Message`nExpected: $Expected`nActual:   $Actual"
    }
    $script:Passed += 1
    Write-Host "  PASS  $Message" -ForegroundColor Green
}

function Invoke-TestGit {
    param([string]$WorkingDirectory, [string[]]$Arguments)
    $output = & git.exe -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Test fixture Git command failed: git -C $WorkingDirectory $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return ($output -join "`n")
}

function Get-FreeTcpPort {
    $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    try {
        $probe.Start()
        return ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port
    }
    finally {
        $probe.Stop()
    }
}

function Invoke-TestRequest {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = ""
    )

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = $Method
    $request.Timeout = 5000
    $request.ReadWriteTimeout = 5000
    $request.AllowAutoRedirect = $false
    foreach ($key in $Headers.Keys) {
        if ($key -eq "Content-Type") { $request.ContentType = [string]$Headers[$key] }
        else { $request.Headers[[string]$key] = [string]$Headers[$key] }
    }
    if ($Body.Length -gt 0) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) }
        finally { $stream.Dispose() }
    }

    $response = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
    }
    catch [System.Net.WebException] {
        if ($null -eq $_.Exception.Response) { throw }
        $response = [System.Net.HttpWebResponse]$_.Exception.Response
    }

    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $responseBody = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
        $headerMap = @{}
        foreach ($key in $response.Headers.AllKeys) { $headerMap[$key] = $response.Headers[$key] }
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $responseBody; Headers = $headerMap }
    }
    finally {
        $response.Dispose()
    }
}

function Start-TestServer {
    param([string]$Repository, [int]$Port)

    $startPath = Join-Path $projectRoot "start.ps1"
    $escape = { param([string]$Value) $Value.Replace("'", "''") }
    $command = @"
`$env:LOCALAPPDATA = '$(& $escape (Join-Path $testRoot "server-state"))'
& '$(& $escape $startPath)' -RepoPath '$(& $escape $Repository)' -Port $Port -NoBrowser -AllowLocalTestRemote
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Process -Id $PID).Path
    $info.Arguments = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -EncodedCommand $encoded"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    return $process
}

try {
    Write-Host "Branchline regression and security tests" -ForegroundColor Cyan
    [void](New-Item -ItemType Directory -Path $testRoot)
    $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION = "1"
    $env:LOCALAPPDATA = Join-Path $testRoot "state"
    $repository = Join-Path $testRoot "working repository"
    $remote = Join-Path $testRoot "remote repository.git"
    [void](New-Item -ItemType Directory -Path $repository)
    [void](New-Item -ItemType Directory -Path $remote)

    & git.exe init --bare $remote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize the disposable remote." }
    & git.exe init -b main $repository | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize the disposable working repository." }
    [void](Invoke-TestGit $repository @("config", "user.name", "Branchline Test"))
    [void](Invoke-TestGit $repository @("config", "user.email", "branchline@example.invalid"))
    Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "# Disposable Branchline repository" -Encoding UTF8
    [void](Invoke-TestGit $repository @("add", "README.md"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Initial test commit"))

    Import-Module $modulePath -Force
    Initialize-GitControlState -RepoPath $repository -Port 4848 -WebRoot $webRoot -AllowLocalTestRemote

    Write-Host "`nLaunch and stop files"
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "RUN-BRANCHLINE.cmd") -PathType Leaf) "includes a one-click run file"
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "STOP-BRANCHLINE.cmd") -PathType Leaf) "includes a one-click stop file"
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "stop.ps1") -PathType Leaf) "includes a verified stop implementation"
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "app.manifest.json") -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal "0.9.1-beta" $manifest.version "declares the beta application version"
    Assert-Equal 1 $manifest.protocolVersion "declares protocol version one"
    $runFileText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "RUN-BRANCHLINE.cmd")
    Assert-True (-not $runFileText.Contains("pause")) "does not leave a batch pause after Ctrl+C"
    $expectedRuntimePath = Get-BranchlineRuntimePath -ProjectRoot $projectRoot -LocalAppDataPath (Join-Path $testRoot "state")
    Assert-True ($expectedRuntimePath.StartsWith((Join-Path $testRoot "state\Branchline\runtime"), [System.StringComparison]::OrdinalIgnoreCase)) "keeps writable runtime state in Local AppData instead of the installation folder"
    Assert-True (-not $expectedRuntimePath.StartsWith(($projectRoot.TrimEnd('\') + '\'), [System.StringComparison]::OrdinalIgnoreCase)) "allows Branchline to run from a read-only installation location"
    $workflowText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot ".github\workflows\windows-ci.yml") -Encoding UTF8
    Assert-True (([regex]::Matches($workflowText, 'shell: powershell -NoProfile -ExecutionPolicy Bypass -File \{0\}')).Count -eq 4) "runs PowerShell CI scripts with File semantics so intentional native failures cannot leak through LASTEXITCODE"
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'state-cache-tests.ps1')) -match '(?m)^exit 0\s*$') "state-cache parity tests explicitly report success after intentional native failures"

    Write-Host "`nState-driven interface"
    $indexText = Get-Content -Raw -LiteralPath (Join-Path $webRoot "index.html") -Encoding UTF8
    $appText = Get-Content -Raw -LiteralPath (Join-Path $webRoot "app.js") -Encoding UTF8
    $stylesText = Get-Content -Raw -LiteralPath (Join-Path $webRoot "styles.css") -Encoding UTF8
    $moduleText = Get-Content -Raw -LiteralPath $modulePath -Encoding UTF8
    $processText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "src\private\GitProcess.ps1") -Encoding UTF8
    $queryText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "src\private\RepositoryQueries.ps1") -Encoding UTF8
    Assert-True ($indexText.Contains('id="localViewTab"') -and $indexText.Contains('id="githubViewTab"')) "separates local work from the fetched GitHub snapshot"
    Assert-True ($indexText.Contains('id="cloneRepositoryButton"') -and $indexText.Contains('id="detachRepositoryButton"')) "offers contextual normal-folder and Git-folder actions"
    Assert-True ($indexText.Contains('id="toggleOutputButton"') -and $appText.Contains("setOutputExpanded")) "lets selected output expand and collapse"
    Assert-True ($stylesText.Contains("body.output-is-expanded .activity-column") -and $stylesText.Contains("z-index: 151")) "keeps expanded output above its blur layer"
    Assert-True ($indexText.Contains('id="identityPanel"') -and $appText.Contains('action: "setIdentity"')) "provides repository-scoped commit identity setup"
    Assert-True ($appText.Contains('action: "adoptRemote"') -and $appText.Contains("Bring GitHub here")) "offers a safe path when GitHub has history but local does not"
    Assert-True ($indexText.Contains('id="connectionBridge"') -and $appText.Contains("Local repository connected to GitHub")) "shows a clear visual bridge between local Git and GitHub"
    Assert-True ($indexText.Contains('id="commitPrerequisiteButton"') -and $appText.Contains("commitPrerequisite.classList.toggle")) "places a blocked commit prerequisite beside the commit controls"
    Assert-True ($appText.Contains("updateActionEmphasis") -and $appText.Contains("is-primary-action")) "emphasizes one safe sync action from repository state"
    Assert-True ($indexText.Contains('id="syncContextPanel"') -and $stylesText.Contains('body.is-local-view #fetchButton') -and $stylesText.Contains('body.is-github-view #pushButton')) "shows local publishing and GitHub receiving controls in their matching views"
    Assert-True ($indexText.Contains('Refresh GitHub snapshot only') -and $appText.Contains('never changes local project files')) "explains that Check GitHub fetches without changing local files"
    Assert-True ($appText.Contains('action: "integrateRemote"') -and $moduleText.Contains('function Invoke-IntegrateRemoteBranch')) "offers an explicit safe integration path when both sides have commits"
    Assert-True ($indexText.Contains('id="mergeSourceSelect"') -and $indexText.Contains('id="mergeTargetSelect"') -and $appText.Contains('action: "mergeBranches"')) "separates branch switching from an explicit source-to-target merge plan"
    Assert-True ($indexText.Contains('Recommended team route') -and $indexText.Contains('Start a new team task') -and $indexText.Contains('Advanced: merge branches locally')) "places the pull-request team flow before advanced local merging"
    Assert-True ($appText.Contains('async function createTeamBranch') -and $appText.Contains('["behind", "diverged"].includes(relationship)') -and $appText.Contains('showSyncGuide("receive")')) "guides a clean stale main through GitHub integration before creating a team branch"
    Assert-True ($indexText.Contains('id="refreshLocalButton"') -and $appText.Contains('refreshLocalFiles') -and $appText.Contains('/api/local-status') -and $appText.Contains('60000') -and -not $appText.Contains('setInterval')) "provides manual and adaptive lightweight local refresh without fetching GitHub"
    Assert-True ($indexText.Contains('Commit staged &amp; publish') -and $appText.Contains('action: "commitStagedPush"') -and $moduleText.Contains('"commitStagedPush"')) "lets already-staged work continue directly to commit and publish"
    Assert-True ($indexText.Contains('id="syncGuideDialog"') -and $indexText.Contains('id="syncGuideSteps"') -and $appText.Contains('function showSyncGuide')) "provides a state-aware synchronization guide box"
    Assert-True ($appText.Contains('showSyncGuide("publish")') -and $appText.Contains('showSyncGuide("receive")')) "explains blocked Publish and Pull actions when they are clicked"
    Assert-True ($appText.Contains('elements.pushButton.disabled = !configured') -and $appText.Contains('elements.pullButton.disabled = !configured')) "keeps configured sync controls clickable so blocked actions can explain themselves"
    Assert-True ($indexText.Contains('id="filePreviewDialog"') -and $appText.Contains('action: "listFiles"') -and $appText.Contains('action: "previewFile"')) "provides paginated read-only local and GitHub file browsers"
    Assert-True ($indexText.Contains('id="repairUpstreamButton"') -and $indexText.Contains('id="checkoutRemoteBranchButton"')) "offers tracking repair and remote-only branch checkout"
    Assert-True ($indexText.Contains('<span>Local scan</span>') -and $indexText.Contains('id="lastUpdated"') -and $indexText.Contains('id="remoteFetchedAt"')) "reports local scan and GitHub fetch times separately"
    Assert-True (-not $moduleText.Contains('Write-Warning "A local request failed."')) "does not alarm users for harmless browser connection cancellations"
    Assert-True (-not $appText.Contains("Legacy") -and -not $moduleText.Contains("Legacy") -and -not $queryText.Contains("Legacy")) "removes obsolete duplicate frontend and backend implementations"
    Assert-True ($appText.Contains("function actionResultMessage") -and $appText.Contains('result.phase === "merge"') -and $appText.Contains("result.commitCreated")) "explains each partial result according to the phase that actually failed"
    Assert-True ($processText.Contains("Stop-BranchlineProcessTree") -and $processText.Contains("completeTreeConfirmed") -and $processText.Contains("WaitForExit(2500)")) "bounds timeout cleanup and reports whether the complete Git process tree stopped"
    Assert-True ($queryText.Contains("-CaptureBytes") -and $queryText.Contains("UTF8Encoding(`$false, `$true)")) "classifies fetched blobs from raw bytes before rendering UTF-8 text"

    Write-Host "`nRemote validation"
    $httpsRemote = ConvertTo-GitHubRemoteValue "https://github.com/Ario971/GitHub_UI"
    Assert-True $httpsRemote.valid "accepts a normal GitHub HTTPS URL"
    Assert-Equal "https://github.com/Ario971/GitHub_UI.git" $httpsRemote.gitUrl "normalizes the HTTPS clone URL"
    $sshRemote = ConvertTo-GitHubRemoteValue "git@github.com:Ario971/GitHub_UI.git"
    Assert-True $sshRemote.valid "accepts a normal GitHub SSH URL"
    Assert-True (-not (ConvertTo-GitHubRemoteValue "https://user:secret@github.com/owner/repo").valid) "rejects embedded credentials"
    Assert-True (-not (ConvertTo-GitHubRemoteValue "https://github.com/owner/repo?token=secret").valid) "rejects query strings"
    Assert-True (-not (ConvertTo-GitHubRemoteValue "file:///C:/Windows/System32").valid) "rejects local URL protocols"
    Assert-True (-not (ConvertTo-GitHubRemoteValue "https://example.com/owner/repo").valid) "rejects non-GitHub hosts"

    Write-Host "`nProcess argument handling"
    Assert-Equal "plain" (ConvertTo-WindowsCommandLineArgument "plain") "leaves simple arguments unquoted"
    Assert-Equal '"two words"' (ConvertTo-WindowsCommandLineArgument "two words") "quotes arguments containing spaces"
    Assert-Equal '""' (ConvertTo-WindowsCommandLineArgument "") "preserves empty arguments"
    Assert-Equal '"ends with slash\\"' (ConvertTo-WindowsCommandLineArgument 'ends with slash\') "escapes a trailing slash inside quotes"

    Write-Host "`nSession and response security"
    $tokenOne = New-SessionToken
    $tokenTwo = New-SessionToken
    Assert-True ($tokenOne -match '^[A-Za-z0-9_-]{43}$') "creates a 256-bit URL-safe session token"
    Assert-True ($tokenOne -cne $tokenTwo) "creates a fresh token for each session"
    $sampleResponse = New-HttpResponse -Body "{}"
    $sampleHeaders = [System.Text.Encoding]::ASCII.GetString($sampleResponse.Header)
    Assert-True ($sampleHeaders.Contains("Content-Security-Policy:")) "adds a Content Security Policy"
    Assert-True ($sampleHeaders.Contains("X-Frame-Options: DENY")) "blocks framing"
    Assert-True (-not $sampleHeaders.Contains("Access-Control-Allow-Origin")) "does not enable CORS"

    Write-Host "`nRepository workflows"
    $summary = Get-AppSummary
    Assert-True $summary.ok "loads a real Git repository"
    Assert-Equal "main" $summary.branch "keeps the repository's current branch"
    Assert-Equal 1 $summary.branches.Count "does not create blank branch entries"
    Assert-Equal "main" $summary.branches[0].name "reports the real branch name"
    Assert-True $summary.identity.configured "reports a usable commit identity"

    $normalFolder = Join-Path $testRoot "normal folder"
    [void](New-Item -ItemType Directory -Path $normalFolder)
    Set-Content -LiteralPath (Join-Path $normalFolder "keep.txt") -Value "Keep this file" -Encoding UTF8
    $inspectedFolder = Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $normalFolder })
    Assert-True $inspectedFolder.ok "inspects a normal folder without treating it as an error"
    $normalSummary = Get-AppSummary
    Assert-True ($normalSummary.folderSelected -and -not $normalSummary.isRepo) "keeps a selected normal folder available for setup"
    Assert-True (-not $normalSummary.folder.empty) "reports whether a normal folder already contains files"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository }))

    $unbornRepository = Join-Path $testRoot "new repository"
    [void](New-Item -ItemType Directory -Path $unbornRepository)
    $noInitialize = Invoke-AppAction ([pscustomobject]@{ action = "initializeRepository"; path = $unbornRepository })
    Assert-True (-not $noInitialize.ok) "requires confirmation before initializing a folder"
    $initialized = Invoke-AppAction ([pscustomobject]@{ action = "initializeRepository"; path = $unbornRepository; confirm = "INITIALIZE" })
    Assert-True $initialized.ok "initializes a new repository without renaming existing branches"
    Set-Content -LiteralPath (Join-Path $unbornRepository "first file.txt") -Value "First content" -Encoding UTF8
    $firstStage = Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = "first file.txt" })
    Assert-True $firstStage.ok "stages the first file before any commit exists"
    Assert-Equal "staged" (@((Get-AppSummary).changedFiles | Where-Object { $_.path -ceq "first file.txt" })[0].state) "reports the unborn repository file as staged"
    $firstUnstage = Invoke-AppAction ([pscustomobject]@{ action = "unstageFile"; file = "first file.txt" })
    Assert-True $firstUnstage.ok "unstages a file before the first commit"
    Assert-Equal "untracked" (@((Get-AppSummary).changedFiles | Where-Object { $_.path -ceq "first file.txt" })[0].state) "returns the first file to untracked state"
    $reselected = Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository })
    Assert-True $reselected.ok "returns to the original working repository"

    $missingConfirmation = Invoke-AppAction ([pscustomobject]@{ action = "configureRemote"; remote = $remote })
    Assert-True (-not $missingConfirmation.ok) "requires confirmation before replacing origin"
    $connected = Invoke-AppAction ([pscustomobject]@{ action = "configureRemote"; remote = $remote; confirm = "CONNECT" })
    Assert-True $connected.ok "connects a validated disposable remote: $($connected.output)"
    Assert-Equal "remote-empty" (Get-AppSummary).tracking.relationship "recognizes an empty remote instead of reporting false synchronization"
    $published = Invoke-AppAction ([pscustomobject]@{ action = "push" })
    Assert-True $published.ok "publishes the current branch explicitly to origin"
    Assert-Equal "in-sync" (Get-AppSummary).tracking.relationship "reports synchronization only after both branch tips match"

    $createdFeatureBranch = Invoke-AppAction ([pscustomobject]@{ action = "createBranch"; branch = "feature/switch-and-merge" })
    Assert-True ($createdFeatureBranch.ok -and (Get-AppSummary).branch -eq "feature/switch-and-merge") "creates and opens a feature branch"
    Set-Content -LiteralPath (Join-Path $repository "branch-work.txt") -Value "Committed on the feature branch" -Encoding UTF8
    [void](Invoke-TestGit $repository @("add", "branch-work.txt"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Feature branch work"))
    $portableChange = Join-Path $repository "portable-local-change.txt"
    Set-Content -LiteralPath $portableChange -Value "Carry this change safely" -Encoding UTF8
    $dirtySwitchToMain = Invoke-AppAction ([pscustomobject]@{ action = "switchBranch"; branch = "main" })
    Assert-True ($dirtySwitchToMain.ok -and (Get-AppSummary).branch -eq "main" -and (Test-Path -LiteralPath $portableChange)) "switches branches while safely carrying a compatible uncommitted file"
    $dirtySwitchBack = Invoke-AppAction ([pscustomobject]@{ action = "switchBranch"; branch = "feature/switch-and-merge" })
    Assert-True ($dirtySwitchBack.ok -and (Get-AppSummary).branch -eq "feature/switch-and-merge" -and (Test-Path -LiteralPath $portableChange)) "carries the same uncommitted file back without data loss"
    Remove-Item -LiteralPath $portableChange
    $unconfirmedBranchMerge = Invoke-AppAction ([pscustomobject]@{ action = "mergeBranches"; source = "feature/switch-and-merge"; target = "main" })
    Assert-True (-not $unconfirmedBranchMerge.ok -and (Get-AppSummary).branch -eq "feature/switch-and-merge") "requires confirmation before switching to a merge target"
    $plannedBranchMerge = Invoke-AppAction ([pscustomobject]@{ action = "mergeBranches"; source = "feature/switch-and-merge"; target = "main"; confirm = "MERGE_BRANCHES:feature/switch-and-merge:main" })
    Assert-True ($plannedBranchMerge.ok -and (Get-AppSummary).branch -eq "main") "switches to the chosen target and merges the chosen source"
    Assert-True (Test-Path -LiteralPath (Join-Path $repository "branch-work.txt")) "preserves feature-branch work in the merge target"
    $mergeParents = (Invoke-TestGit $repository @("rev-list", "--parents", "-n", "1", "HEAD")) -split " "
    Assert-Equal 3 $mergeParents.Count "creates a normal two-parent merge commit"
    $publishedBranchMerge = Invoke-AppAction ([pscustomobject]@{ action = "push" })
    Assert-True ($publishedBranchMerge.ok -and (Get-AppSummary).tracking.relationship -eq "in-sync") "publishes the merged target branch normally"

    $cloneFolder = Join-Path $testRoot "clone destination"
    [void](New-Item -ItemType Directory -Path $cloneFolder)
    $selectedCloneFolder = Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $cloneFolder })
    Assert-True $selectedCloneFolder.ok "selects an empty normal folder for cloning"
    $cloned = Invoke-AppAction ([pscustomobject]@{ action = "cloneRepository"; path = $cloneFolder; remote = $remote; confirm = "CLONE" })
    Assert-True $cloned.ok "clones an existing remote into an empty normal folder"
    Assert-True ((Get-AppSummary).isRepo -and (Test-Path -LiteralPath (Join-Path $cloneFolder "README.md"))) "opens the cloned Git repository and its files"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository }))

    $adoptRepository = Join-Path $testRoot "adopt existing folder"
    [void](New-Item -ItemType Directory -Path $adoptRepository)
    [void](Invoke-TestGit $adoptRepository @("init", "-b", "main"))
    [void](Invoke-TestGit $adoptRepository @("config", "--local", "user.name", " "))
    [void](Invoke-TestGit $adoptRepository @("config", "--local", "user.email", " "))
    Set-Content -LiteralPath (Join-Path $adoptRepository "local-only.txt") -Value "Preserve this local work" -Encoding UTF8
    [void](Invoke-TestGit $adoptRepository @("add", "local-only.txt"))
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $adoptRepository }))
    [void](Invoke-AppAction ([pscustomobject]@{ action = "configureRemote"; remote = $remote; confirm = "CONNECT" }))
    Assert-Equal "local-empty" (Get-AppSummary).tracking.relationship "recognizes GitHub history beside an unborn local repository"
    $blockedEarlyCommit = Invoke-AppAction ([pscustomobject]@{ action = "commit"; message = "Would fork history" })
    Assert-True (-not $blockedEarlyCommit.ok -and $blockedEarlyCommit.output.Contains("Bring GitHub here")) "blocks a commit that would create unrelated history"
    $noAdoptConfirmation = Invoke-AppAction ([pscustomobject]@{ action = "adoptRemote" })
    Assert-True (-not $noAdoptConfirmation.ok) "requires confirmation before adopting GitHub history"
    $adopted = Invoke-AppAction ([pscustomobject]@{ action = "adoptRemote"; confirm = "ADOPT_GITHUB:main" })
    Assert-True $adopted.ok "brings GitHub history into an existing unborn repository"
    Assert-True ((Test-Path -LiteralPath (Join-Path $adoptRepository "README.md")) -and (Get-Content -Raw -LiteralPath (Join-Path $adoptRepository "local-only.txt")).Contains("Preserve this local work")) "adds missing GitHub files without overwriting local work"
    $adoptedSummary = Get-AppSummary
    Assert-True ($adoptedSummary.tracking.relationship -eq "in-sync" -and $adoptedSummary.branch -eq "main") "tracks the adopted GitHub default branch"
    Assert-Equal "untracked" (@($adoptedSummary.changedFiles | Where-Object { $_.path -ceq "local-only.txt" })[0].state) "clears old staging for review after adoption"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = "local-only.txt" }))
    $missingIdentityCommit = Invoke-AppAction ([pscustomobject]@{ action = "commit"; message = "Local work" })
    Assert-True (-not $missingIdentityCommit.ok -and $missingIdentityCommit.output.Contains("author name and email")) "explains missing commit identity before running Git commit"
    $invalidIdentity = Invoke-AppAction ([pscustomobject]@{ action = "setIdentity"; name = "Branchline User"; email = "not-an-email" })
    Assert-True (-not $invalidIdentity.ok) "rejects an invalid commit identity email"
    $savedIdentity = Invoke-AppAction ([pscustomobject]@{ action = "setIdentity"; name = "Branchline User"; email = "branchline.user@example.com" })
    Assert-True ($savedIdentity.ok -and (Get-AppSummary).identity.configured) "saves commit identity only for the active repository"
    $adoptCommit = Invoke-AppAction ([pscustomobject]@{ action = "commit"; message = "Keep local work on GitHub history" })
    Assert-True $adoptCommit.ok "commits local work after adopting GitHub history and setting identity"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository }))

    $detachRepository = Join-Path $testRoot "detach repository"
    [void](New-Item -ItemType Directory -Path $detachRepository)
    [void](Invoke-TestGit $detachRepository @("init", "-b", "main"))
    [void](Invoke-TestGit $detachRepository @("config", "user.name", "Branchline Test"))
    [void](Invoke-TestGit $detachRepository @("config", "user.email", "branchline@example.invalid"))
    Set-Content -LiteralPath (Join-Path $detachRepository "project.txt") -Value "Project content" -Encoding UTF8
    [void](Invoke-TestGit $detachRepository @("add", "project.txt"))
    [void](Invoke-TestGit $detachRepository @("commit", "-m", "Detachable history"))
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $detachRepository }))
    $noDetach = Invoke-AppAction ([pscustomobject]@{ action = "detachRepository" })
    Assert-True (-not $noDetach.ok) "requires typed confirmation before detaching Git metadata"
    $detached = Invoke-AppAction ([pscustomobject]@{ action = "detachRepository"; confirm = "DETACH_GIT:detach repository" })
    Assert-True $detached.ok "turns a Git repository into a normal folder without deleting project files"
    Assert-True ((Test-Path -LiteralPath (Join-Path $detachRepository "project.txt")) -and -not (Test-Path -LiteralPath (Join-Path $detachRepository ".git"))) "preserves files and moves the .git directory"
    $detachedSummary = Get-AppSummary
    $backupName = [string]$detachedSummary.folder.backups[0].name
    Assert-True (-not [string]::IsNullOrWhiteSpace($backupName)) "offers a recoverable Git-history backup"
    $restoredGit = Invoke-AppAction ([pscustomobject]@{ action = "restoreGitMetadata"; path = $detachRepository; backup = $backupName; confirm = "RESTORE_GIT:$backupName" })
    Assert-True ($restoredGit.ok -and (Get-AppSummary).isRepo) "restores detached Git history"
    [void](Invoke-AppAction ([pscustomobject]@{ action = "selectRepository"; path = $repository }))

    Set-Content -LiteralPath (Join-Path $repository ".gitignore") -Value "*.scratch" -Encoding UTF8
    [void](Invoke-TestGit $repository @("add", ".gitignore"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Add dotfile fixture"))
    Set-Content -LiteralPath (Join-Path $repository ".gitignore") -Value @("*.scratch", "*.cache") -Encoding UTF8
    $dotfileSummary = Get-AppSummary
    $dotfileChanges = @($dotfileSummary.changedFiles | Where-Object { $_.path -ceq ".gitignore" })
    Assert-Equal 1 $dotfileChanges.Count "preserves a modified dotfile's exact path"
    Assert-True (@($dotfileSummary.files | Where-Object { $_.path -ceq ".gitignore" }).Count -eq 1) "lists a changed dotfile only once"
    $dotfileRestore = Invoke-AppAction ([pscustomobject]@{ action = "restoreFile"; file = ".gitignore"; confirm = "RESTORE:.gitignore" })
    Assert-True $dotfileRestore.ok "restores a dotfile through its exact path"

    $trickyFile = "notes with spaces.txt"
    Set-Content -LiteralPath (Join-Path $repository $trickyFile) -Value "Line one" -Encoding UTF8
    $changedSummary = Get-AppSummary
    Assert-True (@($changedSummary.changedFiles | Where-Object { $_.path -ceq $trickyFile }).Count -eq 1) "detects an untracked filename containing spaces"
    $staged = Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = $trickyFile })
    Assert-True $staged.ok "stages one exact filename containing spaces"
    $message = 'Handle "quoted" paths and trailing slash\'
    $committed = Invoke-AppAction ([pscustomobject]@{ action = "commit"; message = $message })
    Assert-True $committed.ok "commits a message containing quotes and a trailing slash"
    Assert-Equal $message (Invoke-TestGit $repository @("log", "-1", "--format=%s")) "preserves the exact commit subject"
    $republished = Invoke-AppAction ([pscustomobject]@{ action = "push" })
    Assert-True $republished.ok "publishes a subsequent commit"
    $localHead = Invoke-TestGit $repository @("rev-parse", "HEAD")
    $remoteHead = Invoke-TestGit $remote @("rev-parse", "refs/heads/main")
    Assert-Equal $localHead $remoteHead "remote and local heads match after publish"

    $reopenFile = "staged-before-reopen.txt"
    $unstagedCompanion = "leave-unstaged.txt"
    Set-Content -LiteralPath (Join-Path $repository $reopenFile) -Value "This staging must survive reopening" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $repository $unstagedCompanion) -Value "Do not include me" -Encoding UTF8
    [void](Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = $reopenFile }))
    Initialize-GitControlState -RepoPath $repository -Port 4848 -WebRoot $webRoot -AllowLocalTestRemote
    Assert-Equal "staged" (@((Get-AppSummary).changedFiles | Where-Object { $_.path -ceq $reopenFile })[0].state) "keeps a file staged after the app state is reopened"
    $continuedPublish = Invoke-AppAction ([pscustomobject]@{ action = "commitStagedPush"; message = "Continue staged work after reopening"; confirm = "COMMIT_STAGED_PUSH" })
    Assert-True ($continuedPublish.ok -and (Get-AppSummary).tracking.relationship -eq "in-sync") "commits and publishes work that was staged before reopening"
    Assert-True (-not [string]::IsNullOrWhiteSpace((Invoke-TestGit $repository @("status", "--short", "--", $unstagedCompanion)))) "leaves unrelated unstaged work out of the published commit"
    Remove-Item -LiteralPath (Join-Path $repository $unstagedCompanion)

    $remotePeer = Join-Path $testRoot "remote peer"
    [void](Invoke-TestGit $testRoot @("clone", "--quiet", "--branch", "main", $remote, $remotePeer))
    [void](Invoke-TestGit $remotePeer @("config", "user.name", "Remote Branchline Test"))
    [void](Invoke-TestGit $remotePeer @("config", "user.email", "remote.branchline@example.invalid"))
    Set-Content -LiteralPath (Join-Path $remotePeer "incoming.txt") -Value "Created on the remote side" -Encoding UTF8
    [void](Invoke-TestGit $remotePeer @("add", "incoming.txt"))
    [void](Invoke-TestGit $remotePeer @("commit", "-m", "Incoming remote work"))
    [void](Invoke-TestGit $remotePeer @("push", "--quiet", "origin", "main"))
    Set-Content -LiteralPath (Join-Path $repository "outgoing.txt") -Value "Created on the local side" -Encoding UTF8
    [void](Invoke-TestGit $repository @("add", "outgoing.txt"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Outgoing local work"))
    [void](Invoke-AppAction ([pscustomobject]@{ action = "fetch" }))
    Assert-Equal "diverged" (Get-AppSummary).tracking.relationship "detects when GitHub and local both gained commits"
    $dirtyDuringDivergence = Join-Path $repository "not-yet-saved.txt"
    Set-Content -LiteralPath $dirtyDuringDivergence -Value "Keep this uncommitted work" -Encoding UTF8
    $blockedDirtyIntegration = Invoke-AppAction ([pscustomobject]@{ action = "integrateRemote"; confirm = "MERGE_REMOTE:main" })
    Assert-True (-not $blockedDirtyIntegration.ok -and $blockedDirtyIntegration.output.Contains("every local change")) "blocks integration without discarding an uncommitted local file"
    Assert-True (Test-Path -LiteralPath $dirtyDuringDivergence) "preserves the local file when integration is blocked"
    Remove-Item -LiteralPath $dirtyDuringDivergence
    $unconfirmedIntegration = Invoke-AppAction ([pscustomobject]@{ action = "integrateRemote" })
    Assert-True (-not $unconfirmedIntegration.ok) "requires confirmation before merging diverged GitHub history"
    $integratedRemote = Invoke-AppAction ([pscustomobject]@{ action = "integrateRemote"; confirm = "MERGE_REMOTE:main" })
    Assert-True $integratedRemote.ok "integrates diverged local and GitHub commits with a normal merge: $($integratedRemote.output)"
    Assert-True ((Test-Path -LiteralPath (Join-Path $repository "incoming.txt")) -and (Test-Path -LiteralPath (Join-Path $repository "outgoing.txt"))) "preserves files committed on both sides after integration"
    $integratedSummary = Get-AppSummary
    Assert-True ($integratedSummary.tracking.relationship -eq "ahead" -and $integratedSummary.tracking.behind -eq 0) "unlocks publishing after GitHub history is integrated"
    $publishedIntegration = Invoke-AppAction ([pscustomobject]@{ action = "push" })
    Assert-True ($publishedIntegration.ok -and (Get-AppSummary).tracking.relationship -eq "in-sync") "publishes the integrated history without force pushing"

    $unrelatedWork = Join-Path $testRoot "unrelated source"
    $unrelatedRemote = Join-Path $testRoot "unrelated remote.git"
    [void](New-Item -ItemType Directory -Path $unrelatedWork)
    [void](New-Item -ItemType Directory -Path $unrelatedRemote)
    [void](Invoke-TestGit $unrelatedWork @("init", "-b", "main"))
    [void](Invoke-TestGit $unrelatedWork @("config", "user.name", "Branchline Test"))
    [void](Invoke-TestGit $unrelatedWork @("config", "user.email", "branchline@example.invalid"))
    Set-Content -LiteralPath (Join-Path $unrelatedWork "REMOTE.md") -Value "Different project" -Encoding UTF8
    [void](Invoke-TestGit $unrelatedWork @("add", "REMOTE.md"))
    [void](Invoke-TestGit $unrelatedWork @("commit", "-m", "Unrelated remote history"))
    & git.exe init --bare $unrelatedRemote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize the unrelated disposable remote." }
    [void](Invoke-TestGit $unrelatedWork @("remote", "add", "origin", $unrelatedRemote))
    [void](Invoke-TestGit $unrelatedWork @("push", "--quiet", "-u", "origin", "main"))
    $connectedUnrelated = Invoke-AppAction ([pscustomobject]@{ action = "configureRemote"; remote = $unrelatedRemote; confirm = "CONNECT" })
    Assert-True $connectedUnrelated.ok "connects an unrelated remote for inspection without merging it"
    $unrelatedSummary = Get-AppSummary
    Assert-Equal "unrelated" $unrelatedSummary.tracking.relationship "detects unrelated local and remote histories"
    Assert-True $unrelatedSummary.remoteSnapshot.available "shows the fetched GitHub-side snapshot even when synchronization is blocked"
    $blockedUnrelatedPush = Invoke-AppAction ([pscustomobject]@{ action = "push" })
    Assert-True (-not $blockedUnrelatedPush.ok) "blocks publishing into an unrelated GitHub history"
    $reconnectedOriginal = Invoke-AppAction ([pscustomobject]@{ action = "configureRemote"; remote = $remote; confirm = "CONNECT" })
    Assert-True ($reconnectedOriginal.ok -and (Get-AppSummary).tracking.relationship -eq "in-sync") "recovers cleanly after choosing the correct remote"

    Remove-Item -LiteralPath (Join-Path $repository $trickyFile)
    $deletedFile = @((Get-AppSummary).changedFiles | Where-Object { $_.path -ceq $trickyFile })[0]
    Assert-Equal "deleted" $deletedFile.state "labels an unstaged deletion as deleted"
    $stagedDeletion = Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = $trickyFile })
    Assert-True $stagedDeletion.ok "stages an exact deleted path"
    $stagedDeletedFile = @((Get-AppSummary).changedFiles | Where-Object { $_.path -ceq $trickyFile })[0]
    Assert-Equal "staged" $stagedDeletedFile.state "labels a staged deletion as staged"
    $unstagedDeletion = Invoke-AppAction ([pscustomobject]@{ action = "unstageFile"; file = $trickyFile })
    Assert-True $unstagedDeletion.ok "unstages a staged deletion"
    $restoreDeletion = Invoke-AppAction ([pscustomobject]@{ action = "restoreFile"; file = $trickyFile; confirm = "RESTORE:$trickyFile" })
    Assert-True $restoreDeletion.ok "restores the deleted working-tree file"

    Set-Content -LiteralPath (Join-Path $repository $trickyFile) -Value "Changed but protected" -Encoding UTF8
    $noStageAll = Invoke-AppAction ([pscustomobject]@{ action = "stageAll" })
    Assert-True (-not $noStageAll.ok) "refuses stage-all without its explicit confirmation"
    $noRestore = Invoke-AppAction ([pscustomobject]@{ action = "restoreFile"; file = $trickyFile })
    Assert-True (-not $noRestore.ok) "refuses file restore without its exact confirmation"
    $traversal = Invoke-AppAction ([pscustomobject]@{ action = "stageFile"; file = "..\outside.txt" })
    Assert-True (-not $traversal.ok) "rejects repository path traversal"
    $restored = Invoke-AppAction ([pscustomobject]@{ action = "restoreFile"; file = $trickyFile; confirm = "RESTORE:$trickyFile" })
    Assert-True $restored.ok "restores a tracked file after confirmation"
    Assert-True ((Get-AppSummary).changedFiles.Count -eq 0) "returns the repository to a clean state"

    Set-Content -LiteralPath (Join-Path $repository $trickyFile) -Value "Uncommitted reset guard" -Encoding UTF8
    $currentCommit = Invoke-TestGit $repository @("rev-parse", "HEAD")
    $blockedReset = Invoke-AppAction ([pscustomobject]@{ action = "resetToCommit"; commit = $currentCommit; confirm = "RESET:$currentCommit" })
    Assert-True (-not $blockedReset.ok) "refuses hard reset while uncommitted work exists"
    Assert-Equal "Uncommitted reset guard" ((Get-Content -Raw -LiteralPath (Join-Path $repository $trickyFile)).Trim()) "keeps uncommitted content when reset is refused"
    $cleanupResetGuard = Invoke-AppAction ([pscustomobject]@{ action = "restoreFile"; file = $trickyFile; confirm = "RESTORE:$trickyFile" })
    Assert-True $cleanupResetGuard.ok "cleans up the reset guard fixture"

    [void](Invoke-TestGit $repository @("switch", "-q", "-c", "conflict-source"))
    Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "Conflict source" -Encoding UTF8
    [void](Invoke-TestGit $repository @("add", "README.md"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Create source side of conflict"))
    [void](Invoke-TestGit $repository @("switch", "-q", "main"))
    Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "Conflict main" -Encoding UTF8
    [void](Invoke-TestGit $repository @("add", "README.md"))
    [void](Invoke-TestGit $repository @("commit", "-m", "Create main side of conflict"))
    $conflictedMerge = Invoke-AppAction ([pscustomobject]@{ action = "mergeBranches"; source = "conflict-source"; target = "main"; confirm = "MERGE_BRANCHES:conflict-source:main" })
    Assert-True (-not $conflictedMerge.ok) "reports a real merge conflict without hiding it"
    Assert-Equal "merge" (Get-AppSummary).operation "detects the interrupted merge state"
    $noAbort = Invoke-AppAction ([pscustomobject]@{ action = "abortOperation" })
    Assert-True (-not $noAbort.ok) "requires confirmation before aborting an operation"
    $abortedMerge = Invoke-AppAction ([pscustomobject]@{ action = "abortOperation"; confirm = "ABORT:merge" })
    Assert-True $abortedMerge.ok "aborts an interrupted merge safely"
    Assert-Equal "" (Get-AppSummary).operation "clears the interrupted operation state"
    Assert-True ((Get-AppSummary).changedFiles.Count -eq 0) "restores a clean working tree after aborting the merge"

    Write-Host "`nLive HTTP boundary"
    $port = Get-FreeTcpPort
    $script:ServerProcess = Start-TestServer -Repository $repository -Port $port
    $baseUrl = "http://127.0.0.1:$port"
    $rootResponse = $null
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if ($script:ServerProcess.HasExited) {
            $serverError = $script:ServerProcess.StandardError.ReadToEnd()
            throw "The test server stopped early. $serverError"
        }
        try {
            $rootResponse = Invoke-TestRequest "$baseUrl/"
            if ($rootResponse.Status -eq 200) { break }
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    Assert-True ($null -ne $rootResponse -and $rootResponse.Status -eq 200) "serves the interface only on the local test endpoint"
    Assert-True ($rootResponse.Body -match '<meta name="git-control-token" content="([A-Za-z0-9_-]{43})">') "injects a per-run API token into the interface"
    $liveToken = $Matches[1]
    $aboutResponse = Invoke-TestRequest "$baseUrl/api/about"
    Assert-Equal 200 $aboutResponse.Status "serves installation coordination metadata without a session token"
    $about = $aboutResponse.Body | ConvertFrom-Json
    Assert-Equal "branchline" $about.appId "identifies Branchline at the about endpoint"
    Assert-Equal "0.9.1-beta" $about.version "reports the running version at the about endpoint"
    Assert-Equal "appId,version,protocolVersion,installId" (($about.PSObject.Properties.Name) -join ",") "keeps the about endpoint free of repository paths and session tokens"
    $env:LOCALAPPDATA = Join-Path $testRoot "server-state"
    $duplicateOutput = (& { Start-GitControlPanel -RepoPath $repository -Port $port -WebRoot $webRoot -NoBrowser -AllowLocalTestRemote } 6>&1 | Out-String)
    Assert-True ($duplicateOutput.Contains("already running")) "reuses an existing Branchline session instead of failing on its port"
    $unauthorized = Invoke-TestRequest "$baseUrl/api/summary"
    Assert-Equal 401 $unauthorized.Status "rejects API calls without the token"
    $authorized = Invoke-TestRequest "$baseUrl/api/summary" -Headers @{ "X-Git-Control-Token" = $liveToken }
    Assert-Equal 200 $authorized.Status "accepts a same-origin API call with the token"
    Assert-True (($authorized.Body | ConvertFrom-Json).ok) "returns a valid repository summary over HTTP"
    $localStatus = Invoke-TestRequest "$baseUrl/api/local-status" -Headers @{ "X-Git-Control-Token" = $liveToken }
    Assert-Equal 200 $localStatus.Status "serves the authenticated lightweight local status endpoint"
    Assert-True (($localStatus.Body | ConvertFrom-Json).stateOk) "returns an explicit healthy local-status state"
    $crossOrigin = Invoke-TestRequest "$baseUrl/api/summary" -Headers @{ "X-Git-Control-Token" = $liveToken; "Origin" = "https://attacker.example" }
    Assert-Equal 403 $crossOrigin.Status "rejects a foreign Origin even when the token is present"
    $preflight = Invoke-TestRequest "$baseUrl/api/action" -Method "OPTIONS" -Headers @{ "Origin" = "https://attacker.example" }
    Assert-Equal 405 $preflight.Status "rejects cross-origin preflight requests"
    Assert-True (-not $preflight.Headers.ContainsKey("Access-Control-Allow-Origin")) "omits CORS headers from live responses"

    $runtimeMarker = Join-Path (Get-BranchlineRuntimePath -ProjectRoot $projectRoot -LocalAppDataPath (Join-Path $testRoot "server-state")) "active.json"
    $coordinationClient = New-Object System.Net.Sockets.TcpClient
    try {
        $coordinationClient.Connect("127.0.0.1", $port)
        $partialCoordinationRequest = [System.Text.Encoding]::ASCII.GetBytes("GET /api/about HTTP/1.1`r`nHost: 127.0.0.1`r`n")
        $coordinationClient.GetStream().Write($partialCoordinationRequest, 0, $partialCoordinationRequest.Length)
        Start-Sleep -Milliseconds 250
        Remove-Item -LiteralPath $runtimeMarker -Force
        $busyDuplicateOutput = (& { Start-GitControlPanel -RepoPath $repository -Port $port -WebRoot $webRoot -NoBrowser -AllowLocalTestRemote } 6>&1 | Out-String)
        Assert-True ($busyDuplicateOutput.Contains("No duplicate instance was started")) "uses the per-install mutex when a busy server cannot recreate its deleted marker yet"
    }
    finally { $coordinationClient.Dispose() }
    $markerDeadline = (Get-Date).AddSeconds(10)
    while (-not (Test-Path -LiteralPath $runtimeMarker -PathType Leaf) -and (Get-Date) -lt $markerDeadline) { Start-Sleep -Milliseconds 100 }
    Assert-True (Test-Path -LiteralPath $runtimeMarker -PathType Leaf) "recreates the deleted runtime marker after the busy request finishes"

    $busyClient = New-Object System.Net.Sockets.TcpClient
    try {
        $busyClient.Connect("127.0.0.1", $port)
        $partialRequest = [System.Text.Encoding]::ASCII.GetBytes("GET /api/about HTTP/1.1`r`nHost: 127.0.0.1`r`n")
        $busyClient.GetStream().Write($partialRequest, 0, $partialRequest.Length)
        Start-Sleep -Milliseconds 250
        $stopOutput = (& (Join-Path $projectRoot "stop.ps1") -Port $port 2>&1 6>&1 | Out-String)
    }
    finally { $busyClient.Dispose() }
    Assert-True ($stopOutput.Contains("stopped safely")) "stops a verified Branchline process even while the single-threaded server is busy"
    [void]$script:ServerProcess.WaitForExit(5000)
    Assert-True $script:ServerProcess.HasExited "releases the listening port after the stop command"

    Write-Host "`n$($script:Passed) checks passed." -ForegroundColor Cyan
}
finally {
    if ($null -ne $script:ServerProcess) {
        try {
            if (-not $script:ServerProcess.HasExited) { $script:ServerProcess.Kill() }
            $script:ServerProcess.WaitForExit(5000) | Out-Null
        }
        catch { }
        $script:ServerProcess.Dispose()
    }
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION = $script:OriginalSkipLegacyMigration
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).Path).TrimEnd('\')
        $expectedPrefix = $temporaryBase + '\Branchline-tests-'
        if ($resolvedTestRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
        else {
            Write-Warning "Refused to remove unexpected test path: $resolvedTestRoot"
        }
    }
}
