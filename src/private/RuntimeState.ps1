function Get-BranchlineRuntimePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$LocalAppDataPath = ""
    )

    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) { $LocalAppDataPath = $env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
        $LocalAppDataPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    }
    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
        throw "Windows did not provide a writable Local AppData folder for Branchline runtime state."
    }

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($resolvedProjectRoot.ToUpperInvariant())
        $hashBytes = $hasher.ComputeHash($pathBytes)
    }
    finally {
        $hasher.Dispose()
    }
    $installationKey = -join @($hashBytes[0..15] | ForEach-Object { $_.ToString("x2") })
    return Join-Path ([System.IO.Path]::GetFullPath($LocalAppDataPath)) ("Branchline\runtime\" + $installationKey)
}

function Initialize-BranchlineRuntimePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$LocalAppDataPath = ""
    )

    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $runtimePath = Get-BranchlineRuntimePath -ProjectRoot $resolvedProjectRoot -LocalAppDataPath $LocalAppDataPath
    [System.IO.Directory]::CreateDirectory($runtimePath) | Out-Null

    # Migrate the original installation-local identity once. This lets an
    # upgraded copy safely recognize and stop an older running instance while
    # removing the requirement that the installation directory be writable.
    $legacyRuntimePath = Join-Path $resolvedProjectRoot ".runtime"
    $legacyInstallIdPath = Join-Path $legacyRuntimePath "install-id"
    $installIdPath = Join-Path $runtimePath "install-id"
    $allowLegacyMigration = $env:BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION -cne "1"
    if ($allowLegacyMigration -and -not (Test-Path -LiteralPath $installIdPath -PathType Leaf) -and (Test-Path -LiteralPath $legacyInstallIdPath -PathType Leaf)) {
        try {
            $legacyInstallId = ([System.IO.File]::ReadAllText($legacyInstallIdPath)).Trim()
            if ($legacyInstallId -match '^[a-f0-9]{32}$') {
                [System.IO.File]::WriteAllText($installIdPath, $legacyInstallId, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        catch { }
    }

    $activeStatePath = Join-Path $runtimePath "active.json"
    $legacyActiveStatePath = Join-Path $legacyRuntimePath "active.json"
    if ($allowLegacyMigration -and -not (Test-Path -LiteralPath $activeStatePath -PathType Leaf) -and (Test-Path -LiteralPath $legacyActiveStatePath -PathType Leaf) -and (Test-Path -LiteralPath $installIdPath -PathType Leaf)) {
        try {
            $installId = ([System.IO.File]::ReadAllText($installIdPath)).Trim()
            $legacyActive = Get-Content -Raw -LiteralPath $legacyActiveStatePath -Encoding UTF8 | ConvertFrom-Json
            if (
                [string]$legacyActive.appId -ceq "branchline" -and
                [string]$legacyActive.installId -ceq $installId -and
                [int]$legacyActive.port -ge 1024 -and
                [int]$legacyActive.port -le 65535 -and
                [int]$legacyActive.processId -gt 0
            ) {
                [System.IO.File]::WriteAllText($activeStatePath, ($legacyActive | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        catch { }
    }

    return $runtimePath
}
