[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 4848
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimePath = Join-Path $projectRoot ".runtime"
$installIdPath = Join-Path $runtimePath "install-id"
if (-not (Test-Path -LiteralPath $installIdPath -PathType Leaf)) {
    Write-Host "This Branchline installation has no active runtime identity." -ForegroundColor Yellow
    exit 0
}
$installId = ([System.IO.File]::ReadAllText($installIdPath)).Trim()
if ($installId -notmatch '^[a-f0-9]{32}$') { throw "This Branchline installation identity is invalid. Nothing was stopped." }

function Get-VerifiedAboutOnce {
    param([int]$CandidatePort)
    $response = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$CandidatePort/api/about")
        $request.Method = "GET"
        $request.Timeout = 1500
        $request.ReadWriteTimeout = 1500
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $about = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        if ([string]$about.appId -ceq "branchline" -and [string]$about.installId -ceq $installId) { return $about }
    }
    catch { }
    finally { if ($null -ne $response) { $response.Dispose() } }
    return $null
}

function Get-VerifiedAbout {
    param([int]$CandidatePort)
    for ($attempt = 0; $attempt -lt 3; $attempt += 1) {
        $about = Get-VerifiedAboutOnce $CandidatePort
        if ($null -ne $about) { return $about }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 120 }
    }
    return $null
}

function Test-RecordedProcessStart {
    param([int]$ProcessId, [string]$RecordedStart)
    if ($ProcessId -le 0 -or [string]::IsNullOrWhiteSpace($RecordedStart)) { return $false }
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $recorded = [DateTime]::Parse($RecordedStart).ToUniversalTime()
        return ([Math]::Abs(($process.StartTime.ToUniversalTime() - $recorded).TotalSeconds) -lt 2)
    }
    catch { return $false }
}

$candidatePorts = New-Object System.Collections.Generic.List[int]
$activeProcessId = 0
$activePort = 0
$activeProcessStartedAtUtc = ""
$activeStatePath = Join-Path $runtimePath "active.json"
if (Test-Path -LiteralPath $activeStatePath -PathType Leaf) {
    try {
        $active = Get-Content -Raw -LiteralPath $activeStatePath -Encoding UTF8 | ConvertFrom-Json
        if ([string]$active.installId -ceq $installId) {
            $activePort = [int]$active.port
            $activeProcessId = [int]$active.processId
            if ($null -ne $active.PSObject.Properties["processStartedAtUtc"]) { $activeProcessStartedAtUtc = [string]$active.processStartedAtUtc }
            $candidatePorts.Add($activePort)
        }
    }
    catch { }
}
foreach ($candidatePort in $Port..([Math]::Min(65535, $Port + 20))) {
    if (-not $candidatePorts.Contains($candidatePort)) { $candidatePorts.Add($candidatePort) }
}

$verifiedPort = 0
$processId = 0
foreach ($candidatePort in $candidatePorts) {
    if ($null -ne (Get-VerifiedAbout $candidatePort)) { $verifiedPort = $candidatePort; break }
}
if ($verifiedPort -eq 0) {
    $recordedProcessIsCurrent = Test-RecordedProcessStart -ProcessId $activeProcessId -RecordedStart $activeProcessStartedAtUtc
    $recordedListener = if ($recordedProcessIsCurrent -and $activePort -gt 0) {
        Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $activePort -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.OwningProcess -eq $activeProcessId } |
            Select-Object -First 1
    } else { $null }
    if ($null -ne $recordedListener) {
        # The single-threaded local server cannot answer /api/about while a long
        # Git operation is in progress. The installation ID, PID start time,
        # loopback listener, and owning PID together are the safe fallback.
        $verifiedPort = $activePort
        $processId = $activeProcessId
        Write-Host "Branchline is busy and did not answer, but its recorded process and loopback port were verified." -ForegroundColor Yellow
    }
    elseif ($recordedProcessIsCurrent) {
        Write-Warning "The recorded Branchline process is still alive, but its loopback listener could not be verified. Nothing was stopped and the runtime marker was preserved."
        exit 1
    }
    else {
        Write-Host "This Branchline installation is not running." -ForegroundColor Yellow
        Remove-Item -LiteralPath $activeStatePath -Force -ErrorAction SilentlyContinue
        exit 0
    }
}

if ($processId -le 0 -and $verifiedPort -eq $activePort -and (Test-RecordedProcessStart -ProcessId $activeProcessId -RecordedStart $activeProcessStartedAtUtc)) {
    $processId = $activeProcessId
}
elseif ($processId -le 0) {
    $connection = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $verifiedPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $connection) { $processId = [int]$connection.OwningProcess }
}
if ($processId -le 0) { throw "The verified Branchline endpoint was found, but its owning process could not be verified. Nothing was stopped." }
try {
    Stop-Process -Id $processId -ErrorAction Stop
    Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
}
catch {
    throw "Branchline was found, but Windows did not allow it to be stopped. Close its PowerShell window, or run this stop file as administrator."
}

Remove-Item -LiteralPath $activeStatePath -Force -ErrorAction SilentlyContinue
Write-Host "Branchline stopped safely." -ForegroundColor Green
