function Stop-BranchlineProcessTree {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) {
        return [pscustomobject]@{ stopped = $true; treeConfirmed = $true; detail = "No process was running." }
    }
    try {
        if ($Process.HasExited) {
            return [pscustomobject]@{ stopped = $true; treeConfirmed = $true; detail = "The process had already exited." }
        }
    }
    catch {
        return [pscustomobject]@{ stopped = $false; treeConfirmed = $false; detail = "Windows could not inspect the timed-out process: $($_.Exception.Message)" }
    }

    $taskKill = Join-Path $env:SystemRoot "System32\taskkill.exe"
    $taskKillSucceeded = $false
    $taskKillDetail = ""
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
            try {
                if ($stopProcess.WaitForExit(5000)) {
                    $taskKillSucceeded = ($stopProcess.ExitCode -eq 0)
                    if (-not $taskKillSucceeded) { $taskKillDetail = $stopProcess.StandardError.ReadToEnd().Trim() }
                }
                else {
                    $taskKillDetail = "taskkill did not finish within five seconds."
                    try { $stopProcess.Kill(); [void]$stopProcess.WaitForExit(1000) }
                    catch { $taskKillDetail += " Its helper process could not be stopped cleanly: $($_.Exception.Message)" }
                }
            }
            finally { $stopProcess.Dispose() }
        }
    }
    catch { $taskKillDetail = $_.Exception.Message }

    $parentStopped = $false
    try { $parentStopped = $Process.WaitForExit(2500) } catch { }
    if (-not $parentStopped) {
        try {
            $Process.Kill()
            $parentStopped = $Process.WaitForExit(2500)
        }
        catch {
            if ([string]::IsNullOrWhiteSpace($taskKillDetail)) { $taskKillDetail = $_.Exception.Message }
        }
    }

    $detail = if ($parentStopped -and $taskKillSucceeded) {
        "The complete process tree was stopped."
    }
    elseif ($parentStopped) {
        "The Git parent process stopped, but Windows did not confirm the complete child-process tree.$(if ($taskKillDetail) { " $taskKillDetail" })"
    }
    else {
        "Windows could not confirm that the timed-out Git process stopped.$(if ($taskKillDetail) { " $taskKillDetail" })"
    }
    return [pscustomobject]@{ stopped = $parentStopped; treeConfirmed = ($parentStopped -and $taskKillSucceeded); detail = $detail }
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$DisplayCommand = "git operation",
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 60,
        [switch]$ReadOnly,
        [switch]$CaptureBytes
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
    $stdoutMemory = $null
    try {
        [void]$process.Start()
        if ($CaptureBytes) {
            $stdoutMemory = New-Object System.IO.MemoryStream
            $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutMemory)
        }
        else { $stdoutTask = $process.StandardOutput.ReadToEndAsync() }
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $finished) {
            $termination = Stop-BranchlineProcessTree $process
            $message = "The command exceeded the $TimeoutSeconds second safety limit. $($termination.detail)"
            return New-AppResult -Ok $false -Code 124 -Command $DisplayCommand -Output $message -Phase "timeout" -Recovery @{
                retrySafe = [bool]$termination.stopped
                processStopped = [bool]$termination.stopped
                completeTreeConfirmed = [bool]$termination.treeConfirmed
            }
        }

        if (-not $process.WaitForExit(5000)) { throw "Git reported completion, but Windows did not finalize the process handle safely." }
        $stdoutBytes = $null
        if ($CaptureBytes) {
            if (-not $stdoutTask.Wait(5000)) { throw "Git exited, but its binary output stream did not close safely." }
            $stdoutBytes = $stdoutMemory.ToArray()
            $stdout = ""
        }
        else { $stdout = $stdoutTask.Result }
        $stderr = $stderrTask.Result
        $displayOutput = Join-CommandOutput @($stdout, $stderr)
        $elapsed = ((Get-Date) - $started)
        $duration = [Math]::Round($elapsed.TotalSeconds, 3)
        $result = New-AppResult -Ok ($process.ExitCode -eq 0) -Code $process.ExitCode -Command $DisplayCommand -Output (Limit-Text $displayOutput) -Data @{ durationSeconds = $duration; durationMilliseconds = [Math]::Round($elapsed.TotalMilliseconds, 1) }
        $result | Add-Member -NotePropertyName raw -NotePropertyValue $stdout
        $result | Add-Member -NotePropertyName stderr -NotePropertyValue $stderr
        if ($CaptureBytes) { $result | Add-Member -NotePropertyName bytes -NotePropertyValue $stdoutBytes }
        return $result
    }
    catch {
        return New-AppResult -Ok $false -Code 1 -Command $DisplayCommand -Output "Git could not be started: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $stdoutMemory) { $stdoutMemory.Dispose() }
        $process.Dispose()
    }
}
