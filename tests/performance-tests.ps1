[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeHelperPath = Join-Path $projectRoot "src\private\RuntimeState.ps1"
. $runtimeHelperPath
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $temporaryBase ("Branchline-performance-" + [Guid]::NewGuid().ToString("N"))
$repository = Join-Path $testRoot "five-thousand-files"
$serverProcess = $null
$port = 0
$originalLocalAppData = $env:LOCALAPPDATA
$originalSkipLegacyMigration = $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION

function Invoke-TestGit {
    param([string]$WorkingDirectory, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = & git.exe -C $WorkingDirectory @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw "Fixture Git failed: $($output -join "`n")" }
}

function Get-FreeTcpPort {
    $probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    try { $probe.Start(); return ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port }
    finally { $probe.Stop() }
}

function Invoke-TestRequest {
    param([string]$Url, [hashtable]$Headers = @{})
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = "GET"
    $request.Timeout = 10000
    foreach ($key in $Headers.Keys) { $request.Headers[[string]$key] = [string]$Headers[$key] }
    $response = [System.Net.HttpWebResponse]$request.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    }
    finally { $response.Dispose() }
}

function Invoke-TestJsonRequest {
    param([string]$Url, [hashtable]$Headers, [hashtable]$Payload)
    $json = $Payload | ConvertTo-Json -Compress
    $body = [System.Text.Encoding]::UTF8.GetBytes($json)
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.ContentLength = $body.Length
    $request.Timeout = 15000
    foreach ($key in $Headers.Keys) { $request.Headers[[string]$key] = [string]$Headers[$key] }
    $stream = $request.GetRequestStream()
    try { $stream.Write($body, 0, $body.Length) } finally { $stream.Dispose() }
    $response = [System.Net.HttpWebResponse]$request.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    }
    finally { $response.Dispose() }
}

try {
    Write-Host "Branchline lightweight local-status performance test" -ForegroundColor Cyan
    $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION = "1"
    $env:LOCALAPPDATA = Join-Path $testRoot "state"
    [System.IO.Directory]::CreateDirectory($repository) | Out-Null
    Invoke-TestGit $repository @("init", "-b", "main")
    Invoke-TestGit $repository @("config", "user.name", "Branchline Performance Test")
    Invoke-TestGit $repository @("config", "user.email", "performance@example.invalid")
    $fixtureDirectory = Join-Path $repository "fixture"
    [System.IO.Directory]::CreateDirectory($fixtureDirectory) | Out-Null
    $encoding = New-Object System.Text.UTF8Encoding($false)
    for ($index = 0; $index -lt 5000; $index += 1) {
        [System.IO.File]::WriteAllText((Join-Path $fixtureDirectory ("file-{0:D4}.txt" -f $index)), "fixture $index`n", $encoding)
    }
    Invoke-TestGit $repository @("add", "fixture")
    Invoke-TestGit $repository @("commit", "-m", "Add 5000-file performance fixture")

    $appText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "web\app.js") -Encoding UTF8
    $pollStart = $appText.IndexOf("async function pollLocalStatus()")
    $pollEnd = $appText.IndexOf("function currentCommit()", $pollStart)
    if ($pollStart -lt 0 -or $pollEnd -le $pollStart) { throw "The local polling implementation could not be inspected." }
    $pollBody = $appText.Substring($pollStart, $pollEnd - $pollStart)
    if (-not $pollBody.Contains('/api/local-status') -or $pollBody.Contains('/api/action') -or $pollBody.Contains('fetch') -or $pollBody.Contains('listFiles') -or -not $pollBody.Contains('15000') -or -not $pollBody.Contains('30000') -or -not $pollBody.Contains('60000')) {
        throw "Automatic polling performs work beyond the lightweight local-status request."
    }
    Write-Host "  PASS  automatic polling contains no fetch, remote-tree, log, or file-index action" -ForegroundColor Green

    $port = Get-FreeTcpPort
    $startPath = Join-Path $projectRoot "start.ps1"
    $escapedRoot = $projectRoot.Replace("'", "''")
    $escapedRepo = $repository.Replace("'", "''")
    $escapedState = (Join-Path $testRoot "state").Replace("'", "''")
    $command = "`$env:LOCALAPPDATA='$escapedState'; & '$escapedRoot\start.ps1' -RepoPath '$escapedRepo' -Port $port -NoBrowser"
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Process -Id $PID).Path
    $info.Arguments = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -EncodedCommand $encodedCommand"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $serverProcess = New-Object System.Diagnostics.Process
    $serverProcess.StartInfo = $info
    [void]$serverProcess.Start()

    $baseUrl = "http://127.0.0.1:$port"
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        if ($serverProcess.HasExited) { throw "The performance server stopped early: $($serverProcess.StandardError.ReadToEnd())" }
        try { [void](Invoke-TestRequest "$baseUrl/api/about"); break }
        catch { Start-Sleep -Milliseconds 100 }
    }
    $root = Invoke-TestRequest "$baseUrl/"
    if ($root -notmatch '<meta name="git-control-token" content="([A-Za-z0-9_-]{43})">') { throw "The performance server did not provide a session token." }
    $headers = @{ "X-Git-Control-Token" = $Matches[1] }
    [void](Invoke-TestRequest "$baseUrl/api/local-status" $headers)
    $durations = New-Object System.Collections.Generic.List[double]
    for ($sample = 0; $sample -lt 5; $sample += 1) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $payload = Invoke-TestRequest "$baseUrl/api/local-status" $headers | ConvertFrom-Json
        $stopwatch.Stop()
        if (-not $payload.stateOk) { throw "Local status unexpectedly reported an unhealthy repository." }
        $durations.Add($stopwatch.Elapsed.TotalMilliseconds)
    }
    $ordered = @($durations | Sort-Object)
    $median = [Math]::Round([double]$ordered[2], 1)
    if ($median -gt 750) { throw "Median local-status latency was $median ms, above the 750 ms CI ceiling." }
    $target = if ($median -lt 300) { "target met" } else { "within CI ceiling; optimize toward the 300 ms target" }
    Write-Host "  PASS  median local-status latency: $median ms ($target)" -ForegroundColor Green

    $coldSummaryWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $coldSummary = Invoke-TestRequest "$baseUrl/api/summary" $headers | ConvertFrom-Json
    $coldSummaryWatch.Stop()
    if (-not $coldSummary.stateOk -or $null -eq $coldSummary.revisions) { throw "Cold summary did not return healthy revisioned state." }
    if ($coldSummaryWatch.Elapsed.TotalMilliseconds -gt 1500) { throw "Cold summary exceeded the 1500 ms CI ceiling." }
    $warmSummaryDurations = New-Object System.Collections.Generic.List[double]
    for ($sample = 0; $sample -lt 7; $sample += 1) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        [void](Invoke-TestRequest "$baseUrl/api/summary" $headers)
        $watch.Stop()
        $warmSummaryDurations.Add($watch.Elapsed.TotalMilliseconds)
    }
    $warmSummaryMedian = [Math]::Round([double](@($warmSummaryDurations | Sort-Object)[3]), 1)
    if ($warmSummaryMedian -gt 350) { throw "Warm summary median was $warmSummaryMedian ms, above 350 ms." }
    Write-Host "  PASS  cold summary $([Math]::Round($coldSummaryWatch.Elapsed.TotalMilliseconds, 1)) ms; warm median $warmSummaryMedian ms" -ForegroundColor Green

    $pagePayload = @{ action = "listFiles"; side = "local"; query = ""; offset = 0; limit = 100 }
    $coldPageWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $coldPage = Invoke-TestJsonRequest "$baseUrl/api/action" $headers $pagePayload | ConvertFrom-Json
    $coldPageWatch.Stop()
    $warmPageWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $warmPage = Invoke-TestJsonRequest "$baseUrl/api/action" $headers $pagePayload | ConvertFrom-Json
    $warmPageWatch.Stop()
    if ($coldPage.page.total -ne 5000 -or $warmPage.page.total -ne 5000 -or [string]::IsNullOrWhiteSpace([string]$warmPage.page.revision)) { throw "The cached file index returned incomplete pagination state." }
    if ($coldPageWatch.Elapsed.TotalMilliseconds -gt 1200 -or $warmPageWatch.Elapsed.TotalMilliseconds -gt 350) { throw "File index timing exceeded the cold/warm CI ceilings: $([Math]::Round($coldPageWatch.Elapsed.TotalMilliseconds, 1)) / $([Math]::Round($warmPageWatch.Elapsed.TotalMilliseconds, 1)) ms." }
    if ($null -eq $warmPage.refreshScope -or $warmPage.refreshScope.full) { throw "Read-only file browsing did not return a no-refresh action scope." }
    Write-Host "  PASS  local file index cold $([Math]::Round($coldPageWatch.Elapsed.TotalMilliseconds, 1)) ms; warm $([Math]::Round($warmPageWatch.Elapsed.TotalMilliseconds, 1)) ms" -ForegroundColor Green

    $serverProcess.Refresh()
    $memoryBefore = $serverProcess.WorkingSet64
    for ($sample = 0; $sample -lt 100; $sample += 1) { [void](Invoke-TestRequest "$baseUrl/api/summary" $headers) }
    $serverProcess.Refresh()
    $growth = [Math]::Max(0, $serverProcess.WorkingSet64 - $memoryBefore)
    if ($growth -gt 32MB) { throw "Repeated cached summaries grew server memory by more than 32 MiB." }
    Write-Host "  PASS  100 cached summaries stayed within the memory-growth limit" -ForegroundColor Green

    $runtimeState = Join-Path (Get-BranchlineRuntimePath -ProjectRoot $projectRoot -LocalAppDataPath (Join-Path $testRoot "state")) "active.json"
    if (-not (Test-Path -LiteralPath $runtimeState -PathType Leaf)) { throw "The running server did not create active runtime state." }
    Remove-Item -LiteralPath $runtimeState -Force
    $runtimeDeadline = (Get-Date).AddSeconds(7)
    while ((Get-Date) -lt $runtimeDeadline -and -not (Test-Path -LiteralPath $runtimeState -PathType Leaf)) { Start-Sleep -Milliseconds 150 }
    if (-not (Test-Path -LiteralPath $runtimeState -PathType Leaf)) { throw "The live server did not recreate its missing runtime marker." }
    $active = Get-Content -Raw -LiteralPath $runtimeState -Encoding UTF8 | ConvertFrom-Json
    if ([int]$active.processId -ne $serverProcess.Id -or [string]::IsNullOrWhiteSpace([string]$active.processStartedAtUtc)) { throw "The recreated runtime marker did not preserve process identity." }
    Write-Host "  PASS  live server recreated a deleted runtime marker safely" -ForegroundColor Green
}
finally {
    if ($null -ne $serverProcess) {
        try {
            & (Join-Path $projectRoot "stop.ps1") -Port $port 2>&1 | Out-Null
            if (-not $serverProcess.HasExited) { [void]$serverProcess.WaitForExit(5000) }
            if (-not $serverProcess.HasExited) { $serverProcess.Kill() }
        }
        catch { try { if (-not $serverProcess.HasExited) { $serverProcess.Kill() } } catch { } }
        $serverProcess.Dispose()
    }
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testRoot).Path).TrimEnd('\')
        if ($resolved.StartsWith($temporaryBase + '\Branchline-performance-', [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION = $originalSkipLegacyMigration
}
