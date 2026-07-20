function New-BranchlineAboutPayload {
    return [ordered]@{
        appId = "branchline"
        version = $script:AppState.Version
        protocolVersion = $script:AppState.ProtocolVersion
        installId = $script:AppState.InstallId
    }
}

function Write-BranchlineActiveRuntimeState {
    param([string]$Path, [int]$Port)
    $payload = [ordered]@{
        appId = "branchline"
        version = $script:AppState.Version
        protocolVersion = $script:AppState.ProtocolVersion
        installId = $script:AppState.InstallId
        port = $Port
        processId = $PID
        processStartedAtUtc = $script:AppState.ProcessStartedAtUtc
        startedAt = (Get-Date).ToString("o")
    }
    [System.IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
}

function Ensure-BranchlineActiveRuntimeState {
    param([string]$Path, [int]$Port)
    $matches = $false
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $active = Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
            $matches = (
                [string]$active.appId -ceq "branchline" -and
                [string]$active.installId -ceq $script:AppState.InstallId -and
                [string]$active.version -ceq $script:AppState.Version -and
                [int]$active.protocolVersion -eq $script:AppState.ProtocolVersion -and
                [int]$active.port -eq $Port -and
                [int]$active.processId -eq $PID -and
                [string]$active.processStartedAtUtc -ceq $script:AppState.ProcessStartedAtUtc
            )
        }
        catch { $matches = $false }
    }
    if (-not $matches) { Write-BranchlineActiveRuntimeState -Path $Path -Port $Port }
}

function Test-MatchingBranchlineInstance {
    param([object]$About)
    return (
        $null -ne $About -and
        [string]$About.appId -ceq "branchline" -and
        [string]$About.installId -ceq $script:AppState.InstallId -and
        [string]$About.version -ceq $script:AppState.Version -and
        [int]$About.protocolVersion -eq $script:AppState.ProtocolVersion
    )
}
