function Stop-BranchlineProcessTree {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process -or $Process.HasExited) { return }
    $taskKill = Join-Path $env:SystemRoot "System32\taskkill.exe"
    try {
        if (Test-Path -LiteralPath $taskKill -PathType Leaf) {
            $stopInfo = New-Object System.Diagnostics.ProcessStartInfo
            $stopInfo.FileName = $taskKill
            $stopInfo.Arguments = "/PID $($Process.Id) /T /F"
            $stopInfo.UseShellExecute = $false
            $stopInfo.CreateNoWindow = $true
            $stopInfo.RedirectStandardOutput = $true
            $stopInfo.RedirectStandardError = $true
            $stopProcess = [System.Diagnostics.Process]::Start($stopInfo)
            try { [void]$stopProcess.WaitForExit(5000) } finally { $stopProcess.Dispose() }
        }
    }
    catch { }
    if (-not $Process.HasExited) {
        try { $Process.Kill() } catch { }
    }
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$DisplayCommand = "git operation",
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 60,
        [switch]$ReadOnly
    )

    if ([string]::IsNullOrWhiteSpace($script:AppState.GitPath)) { throw "Git is not initialized." }
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        return New-AppResult -Ok $false -Code 1 -Command $DisplayCommand -Output "Working directory was not found."
    }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:AppState.GitPath
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument ([string]$_) }) -join " "
    $info.WorkingDirectory = $WorkingDirectory
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $gitEnvironment = [ordered]@{
        GIT_TERMINAL_PROMPT = "0"
        GCM_INTERACTIVE = "Never"
        GIT_PAGER = "cat"
        GIT_EDITOR = "true"
        GIT_MERGE_AUTOEDIT = "no"
        LC_ALL = "C"
        LANG = "C"
    }
    if ($ReadOnly) { $gitEnvironment.GIT_OPTIONAL_LOCKS = "0" }
    $hasModernEnvironment = ($null -ne $info.PSObject.Properties["Environment"] -and $null -ne $info.Environment)
    foreach ($environmentName in $gitEnvironment.Keys) {
        if ($hasModernEnvironment) { $info.Environment[$environmentName] = $gitEnvironment[$environmentName] }
        else { $info.EnvironmentVariables[$environmentName] = $gitEnvironment[$environmentName] }
    }
    try {
        $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch { }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $started = Get-Date
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $finished) {
            Stop-BranchlineProcessTree $process
            try { $process.WaitForExit() } catch { }
            return New-AppResult -Ok $false -Code 124 -Command $DisplayCommand -Output "The command exceeded the $TimeoutSeconds second safety limit and its complete process tree was stopped." -Phase "timeout" -Recovery @{ retrySafe = $true }
        }

        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $displayOutput = Join-CommandOutput @($stdout, $stderr)
        $elapsed = ((Get-Date) - $started)
        $duration = [Math]::Round($elapsed.TotalSeconds, 3)
        $result = New-AppResult -Ok ($process.ExitCode -eq 0) -Code $process.ExitCode -Command $DisplayCommand -Output (Limit-Text $displayOutput) -Data @{ durationSeconds = $duration; durationMilliseconds = [Math]::Round($elapsed.TotalMilliseconds, 1) }
        $result | Add-Member -NotePropertyName raw -NotePropertyValue $stdout
        $result | Add-Member -NotePropertyName stderr -NotePropertyValue $stderr
        return $result
    }
    catch {
        return New-AppResult -Ok $false -Code 1 -Command $DisplayCommand -Output "Git could not be started: $($_.Exception.Message)"
    }
    finally { $process.Dispose() }
}
