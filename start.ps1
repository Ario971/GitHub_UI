[CmdletBinding()]
param(
    [string]$RepoPath = "",
    [ValidateRange(1024, 65535)]
    [int]$Port = 4848,
    [switch]$NoBrowser,
    [switch]$AllowLocalTestRemote
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $projectRoot "src\GitControlPanel.psm1"
$webRoot = Join-Path $projectRoot "web"
$manifestPath = Join-Path $projectRoot "app.manifest.json"
$runtimePath = Join-Path $projectRoot ".runtime"

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Application module was not found: $modulePath"
}
if (-not (Test-Path -LiteralPath $webRoot -PathType Container)) {
    throw "Web assets were not found: $webRoot"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Application manifest was not found: $manifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
if ([string]$manifest.appId -cne "branchline" -or [string]::IsNullOrWhiteSpace([string]$manifest.version)) {
    throw "Application manifest is invalid. Reinstall Branchline from a trusted source."
}
[System.IO.Directory]::CreateDirectory($runtimePath) | Out-Null
$installIdPath = Join-Path $runtimePath "install-id"
$installId = if (Test-Path -LiteralPath $installIdPath -PathType Leaf) { ([System.IO.File]::ReadAllText($installIdPath)).Trim() } else { "" }
if ($installId -notmatch '^[a-f0-9]{32}$') {
    $installId = [Guid]::NewGuid().ToString("N")
    [System.IO.File]::WriteAllText($installIdPath, $installId, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-BranchlineAboutOnce {
    param([int]$CandidatePort)
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$CandidatePort/api/about")
        $request.Method = "GET"
        $request.Timeout = 1500
        $request.ReadWriteTimeout = 1500
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
        finally { $reader.Dispose() }
    }
    catch { return $null }
    finally { if ($null -ne $response) { $response.Dispose() } }
}

function Get-BranchlineAbout {
    param([int]$CandidatePort)
    for ($attempt = 0; $attempt -lt 3; $attempt += 1) {
        $about = Get-BranchlineAboutOnce $CandidatePort
        if ($null -ne $about) { return $about }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 120 }
    }
    return $null
}

function Test-RecordedBranchlineProcess {
    param([object]$Active)
    try {
        $process = Get-Process -Id ([int]$Active.processId) -ErrorAction Stop
        if ($null -eq $Active.PSObject.Properties["processStartedAtUtc"] -or [string]::IsNullOrWhiteSpace([string]$Active.processStartedAtUtc)) { return $false }
        $recorded = [DateTime]::Parse([string]$Active.processStartedAtUtc).ToUniversalTime()
        return ([Math]::Abs(($process.StartTime.ToUniversalTime() - $recorded).TotalSeconds) -lt 2)
    }
    catch { return $false }
}

$activeStatePath = Join-Path $runtimePath "active.json"
if (Test-Path -LiteralPath $activeStatePath -PathType Leaf) {
    try {
        $active = Get-Content -Raw -LiteralPath $activeStatePath -Encoding UTF8 | ConvertFrom-Json
        $activePort = [int]$active.port
        $about = Get-BranchlineAbout $activePort
        if ($null -ne $about -and [string]$about.appId -ceq "branchline" -and [string]$about.installId -ceq $installId) {
            $activeUrl = "http://127.0.0.1:$activePort/"
            if ([string]$about.version -ceq [string]$manifest.version -and [int]$about.protocolVersion -eq [int]$manifest.protocolVersion) {
                Write-Host "Branchline $($manifest.version) is already running at $activeUrl" -ForegroundColor Yellow
                if (-not $NoBrowser) { Start-Process $activeUrl | Out-Null }
                return
            }
            $activeProcess = if (Test-RecordedBranchlineProcess $active) { Get-Process -Id ([int]$active.processId) -ErrorAction SilentlyContinue } else { $null }
            if ($null -ne $activeProcess) {
                Write-Host "Restarting the verified older Branchline instance..." -ForegroundColor Yellow
                Stop-Process -Id ([int]$active.processId) -ErrorAction Stop
                Wait-Process -Id ([int]$active.processId) -Timeout 5 -ErrorAction SilentlyContinue
            }
        }
        elseif ($null -eq $about) {
            if (Test-RecordedBranchlineProcess $active) {
                Write-Warning "The verified Branchline process is still running but did not answer yet. No duplicate instance was started. Wait a moment, then run Branchline again or use STOP-BRANCHLINE.cmd."
                return
            }
            Remove-Item -LiteralPath $activeStatePath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "The saved runtime state was stale and will be replaced: $($_.Exception.Message)"
        Remove-Item -LiteralPath $activeStatePath -Force -ErrorAction SilentlyContinue
    }
}

Import-Module $modulePath -Force
Start-GitControlPanel -RepoPath $RepoPath -Port $Port -WebRoot $webRoot -ProjectRoot $projectRoot -InstallId $installId -NoBrowser:$NoBrowser -AllowLocalTestRemote:$AllowLocalTestRemote
