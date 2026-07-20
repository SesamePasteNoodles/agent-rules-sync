[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Alias('h')]
    [switch]$Help,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:LastCommandExitCode = 0
. (Join-Path $PSScriptRoot 'AgentRules.Common.ps1')

function Write-AgentRulesMenuHeader {
    Clear-Host
    Write-Host '========================================' -ForegroundColor DarkCyan
    Write-Host 'AI Agent 規範管理工具' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor DarkCyan
    Write-Host
}

function Write-AgentRulesUsage {
    Write-Host 'AI Agent 規範管理工具' -ForegroundColor Cyan
    Write-Host
    Write-Host '直接雙擊 AgentRules.cmd 可開啟互動選單。'
    Write-Host
    Write-Host '命令列用法：'
    Write-Host '  AgentRules.cmd check'
    Write-Host '  AgentRules.cmd preview'
    Write-Host '  AgentRules.cmd sync'
    Write-Host '  AgentRules.cmd codex'
    Write-Host '  AgentRules.cmd antigravity'
    Write-Host '  AgentRules.cmd build'
    Write-Host '  AgentRules.cmd test'
    Write-Host '  AgentRules.cmd cleanup'
    Write-Host '  AgentRules.cmd cleanup --apply'
    Write-Host '  AgentRules.cmd restore'
    Write-Host '  AgentRules.cmd restore <BackupId> [--target Codex|Antigravity|All] [--apply]'
    Write-Host '  AgentRules.cmd help'
    Write-Host
    Write-Host '注意：sync、codex、antigravity、cleanup --apply 與 restore --apply 會立即套用變更。' -ForegroundColor Yellow
}

function Invoke-AgentRulesChildScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path $script:RepositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Host "[ERROR] 找不到必要腳本：$scriptPath" -ForegroundColor Red
        $script:LastCommandExitCode = 2
        return
    }

    # Keep the child process attached to the current console so Write-Host colors are preserved.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
    $script:LastCommandExitCode = $LASTEXITCODE
}

function Invoke-AgentRulesCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('check', 'preview', 'sync', 'codex', 'antigravity', 'build', 'test', 'cleanup', 'restore')]
        [string]$Name,

        [string[]]$Arguments = @()
    )

    switch ($Name) {
        'check' {
            Invoke-AgentRulesChildScript -RelativePath 'scripts\Check-AgentRules.ps1' -Arguments @('-Target', 'All')
        }
        'preview' {
            Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'All')
        }
        'sync' {
            Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'All', '-Apply')
        }
        'codex' {
            Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'Codex', '-Apply')
        }
        'antigravity' {
            Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'Antigravity', '-Apply')
        }
        'build' {
            Invoke-AgentRulesChildScript -RelativePath 'scripts\Build-AgentRules.ps1' -Arguments @('-Target', 'All')
        }
        'test' {
            Invoke-AgentRulesChildScript -RelativePath 'tests\Test-AgentRules.ps1'
        }
        'cleanup' {
            Invoke-AgentRulesChildScript `
                -RelativePath 'scripts\Cleanup-AgentRulesBackups.ps1' `
                -Arguments $Arguments
        }
        'restore' {
            Invoke-AgentRulesChildScript `
                -RelativePath 'scripts\Restore-AgentRulesBackup.ps1' `
                -Arguments $Arguments
        }
    }
}

function Confirm-AgentRulesSync {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDescription
    )

    Write-Host
    Write-Host "即將更新 $TargetDescription 的全域規範。" -ForegroundColor Yellow
    $confirmation = Read-Host '是否繼續？[y/N]'
    if (($null -ne $confirmation) -and ($confirmation.Trim() -ieq 'y')) {
        return $true
    }

    Write-Host '已取消。' -ForegroundColor DarkYellow
    return $false
}

function Show-AgentRulesCommandResult {
    param([Parameter(Mandatory = $true)][int]$ExitCode)

    Write-Host
    $color = if ($ExitCode -eq 0) { 'Green' } else { 'Yellow' }
    Write-Host "執行完畢，結束碼：$ExitCode" -ForegroundColor $color
    $null = Read-Host '按 Enter 返回選單'
}

function Get-AgentRulesRestoreChoices {
    $backupRoot = Join-Path $script:RepositoryRoot 'backups'
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        return @()
    }

    $choices = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force)) {
        if ($directory.Name -notmatch '^\d{8}-\d{6}-\d{3}$') {
            continue
        }
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(
            $directory.Name,
            'yyyyMMdd-HHmmss-fff',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsed
        )) {
            continue
        }

        $targets = @()
        $fileCount = 0
        foreach ($targetName in @('Codex', 'Antigravity')) {
            $targetRoot = Join-Path $directory.FullName $targetName.ToLowerInvariant()
            if (Test-Path -LiteralPath $targetRoot -PathType Container) {
                $targets += $targetName
                $fileCount += @(
                    Get-ChildItem -LiteralPath $targetRoot -Recurse -File -Force -ErrorAction Stop
                ).Count
            }
        }
        if ($targets.Count -gt 0) {
            $choices += [pscustomobject]@{
                BackupId = $directory.Name
                Targets = $targets
                FileCount = $fileCount
            }
        }
    }

    return @($choices | Sort-Object BackupId -Descending)
}

function Invoke-AgentRulesRestoreMenu {
    $choices = @(Get-AgentRulesRestoreChoices)
    if ($choices.Count -eq 0) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message '沒有可回復的標準時間戳備份。'
        $script:LastCommandExitCode = 0
        return
    }

    Write-Host '可回復的備份（只包含當次同步前被覆寫的檔案）：'
    for ($index = 0; $index -lt $choices.Count; $index++) {
        $choice = $choices[$index]
        Write-Host (
            '  {0}. {1}  {2}  {3} 個檔案' -f
            ($index + 1),
            $choice.BackupId,
            ($choice.Targets -join ', '),
            $choice.FileCount
        )
    }
    Write-AgentRulesLog -Level 'SUMMARY' -Message "共 $($choices.Count) 份備份；請輸入序號選擇。"

    Write-Host
    while ($true) {
        $selection = Read-Host '請輸入要回復的備份序號（直接按 Enter 取消）'
        if (($null -eq $selection) -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Host '已取消。' -ForegroundColor DarkYellow
            return
        }

        $selectedIndex = 0
        if ([int]::TryParse($selection.Trim(), [ref]$selectedIndex) -and
            ($selectedIndex -ge 1) -and
            ($selectedIndex -le $choices.Count)) {
            break
        }
        Write-Host "[ERROR] 無效的序號，請輸入 1 到 $($choices.Count)。" -ForegroundColor Red
    }
    $backupId = $choices[$selectedIndex - 1].BackupId
    Write-Host "已選擇：$selectedIndex. $backupId" -ForegroundColor Cyan

    $target = Read-Host '目標 Codex、Antigravity 或 All [All]'
    if (($null -eq $target) -or [string]::IsNullOrWhiteSpace($target)) {
        $target = 'All'
    }
    $normalizedTarget = switch ($target.Trim().ToLowerInvariant()) {
        'codex' { 'Codex' }
        'antigravity' { 'Antigravity' }
        'all' { 'All' }
        default { $null }
    }
    if ($null -eq $normalizedTarget) {
        Write-Host '[ERROR] 目標必須是 Codex、Antigravity 或 All。' -ForegroundColor Red
        $script:LastCommandExitCode = 2
        return
    }

    $arguments = @($backupId, '--target', $normalizedTarget)
    Invoke-AgentRulesCommand -Name 'restore' -Arguments $arguments
    if ($script:LastCommandExitCode -ne 0) {
        return
    }

    Write-Host
    Write-Host '只會回復上方列出的備份檔案，不會刪除其他檔案。' -ForegroundColor Yellow
    $confirmation = Read-Host '是否套用回復？[y/N]'
    if (($null -eq $confirmation) -or ($confirmation.Trim() -ine 'y')) {
        Write-Host '已取消。' -ForegroundColor DarkYellow
        return
    }

    Invoke-AgentRulesCommand -Name 'restore' -Arguments ($arguments + '--apply')
}

function Read-AgentRulesDestination {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Codex', 'Antigravity')]
        [string]$TargetName,

        [string]$CurrentPath
    )

    while ($true) {
        $prompt = if ([string]::IsNullOrWhiteSpace($CurrentPath)) {
            "$TargetName 全域目錄"
        }
        else {
            "$TargetName 全域目錄（直接按 Enter 保留 $CurrentPath）"
        }
        $inputPath = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) {
                return $CurrentPath
            }
            Write-Host '[ERROR] 目錄不可為空。' -ForegroundColor Red
            continue
        }

        try {
            $resolvedPath = ConvertTo-AgentRulesDestinationPath -Path $inputPath
            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container -ErrorAction Stop)) {
                Write-Host "目錄尚不存在：$resolvedPath" -ForegroundColor Yellow
                $confirmation = Read-Host '是否採用，並在同步時建立？[y/N]'
                if (($null -eq $confirmation) -or ($confirmation.Trim() -ine 'y')) {
                    continue
                }
            }
            return $resolvedPath
        }
        catch {
            Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Confirm-AgentRulesDestinations {
    param(
        [Parameter(Mandatory = $true)][string]$CodexDestination,
        [Parameter(Mandatory = $true)][string]$AntigravityDestination
    )

    Write-Host
    Write-Host '準備儲存以下全域目錄：' -ForegroundColor Cyan
    Write-Host "  Codex：       $CodexDestination"
    Write-Host "  Antigravity： $AntigravityDestination"
    Write-Host
    $confirmation = Read-Host '是否儲存？[y/N]'
    return ($null -ne $confirmation) -and ($confirmation.Trim() -ieq 'y')
}

function Save-AgentRulesDestinationsInteractive {
    param(
        [Parameter(Mandatory = $true)][string]$CodexDestination,
        [Parameter(Mandatory = $true)][string]$AntigravityDestination
    )

    if (-not (Confirm-AgentRulesDestinations `
        -CodexDestination $CodexDestination `
        -AntigravityDestination $AntigravityDestination)) {
        Write-Host '已取消，未變更設定。' -ForegroundColor DarkYellow
        return $false
    }

    try {
        $settings = Save-AgentRulesUserSettings `
            -CodexDestination $CodexDestination `
            -AntigravityDestination $AntigravityDestination
        Write-Host "已儲存設定：$($settings.SettingsPath)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ERROR] 無法儲存設定：$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-AgentRulesManualDirectorySetup {
    param($CurrentSettings)

    $currentCodex = if ($null -eq $CurrentSettings) {
        $null
    }
    else {
        [string]$CurrentSettings.Destinations.Codex
    }
    $currentAntigravity = if ($null -eq $CurrentSettings) {
        $null
    }
    else {
        [string]$CurrentSettings.Destinations.Antigravity
    }

    Write-Host
    $codexDestination = Read-AgentRulesDestination `
        -TargetName 'Codex' `
        -CurrentPath $currentCodex
    $antigravityDestination = Read-AgentRulesDestination `
        -TargetName 'Antigravity' `
        -CurrentPath $currentAntigravity
    return Save-AgentRulesDestinationsInteractive `
        -CodexDestination $codexDestination `
        -AntigravityDestination $antigravityDestination
}

function Invoke-AgentRulesDirectoryDetection {
    Write-Host
    Write-Host '正在偵測 Agent 全域目錄（每個 Agent 最多嘗試 3 個位置）……' -ForegroundColor Cyan
    $codexResult = Find-AgentRulesGlobalDirectory -TargetName 'Codex' -MaximumAttempts 3
    $antigravityResult = Find-AgentRulesGlobalDirectory -TargetName 'Antigravity' -MaximumAttempts 3

    $codexDescription = if ($codexResult.Success) { $codexResult.Path } else { '未找到' }
    $antigravityDescription = if ($antigravityResult.Success) { $antigravityResult.Path } else { '未找到' }
    $codexColor = if ($codexResult.Success) { 'Green' } else { 'Yellow' }
    $antigravityColor = if ($antigravityResult.Success) { 'Green' } else { 'Yellow' }
    Write-Host ("Codex：       {0}（嘗試 {1} 次）" -f $codexDescription, $codexResult.AttemptCount) `
        -ForegroundColor $codexColor
    Write-Host ("Antigravity： {0}（嘗試 {1} 次）" -f $antigravityDescription, $antigravityResult.AttemptCount) `
        -ForegroundColor $antigravityColor

    $codexDestination = if ($codexResult.Success) {
        $codexResult.Path
    }
    else {
        Write-Host
        Write-Host 'Codex 偵測失敗，請手動輸入。' -ForegroundColor Yellow
        Read-AgentRulesDestination -TargetName 'Codex'
    }
    $antigravityDestination = if ($antigravityResult.Success) {
        $antigravityResult.Path
    }
    else {
        Write-Host
        Write-Host 'Antigravity 偵測失敗，請手動輸入。' -ForegroundColor Yellow
        Read-AgentRulesDestination -TargetName 'Antigravity'
    }

    return Save-AgentRulesDestinationsInteractive `
        -CodexDestination $codexDestination `
        -AntigravityDestination $antigravityDestination
}

function Get-AgentRulesSettingsForMenu {
    try {
        return (Read-AgentRulesUserSettings)
    }
    catch {
        Write-Host "[WARN] $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '請重新設定 Agent 全域目錄。' -ForegroundColor Yellow
        return $null
    }
}

function Initialize-AgentRulesDirectories {
    if ($null -ne (Get-AgentRulesSettingsForMenu)) {
        return $true
    }

    while ($true) {
        Write-AgentRulesMenuHeader
        Write-Host '尚未設定 Agent 全域目錄。' -ForegroundColor Yellow
        Write-Host
        Write-Host '1. 自動偵測'
        Write-Host '2. 手動輸入'
        Write-Host '0. 離開'
        Write-Host

        $selection = Read-Host '請選擇'
        if ($null -eq $selection) {
            return $false
        }
        switch ($selection.Trim()) {
            '1' {
                if (Invoke-AgentRulesDirectoryDetection) {
                    return $true
                }
            }
            '2' {
                if (Invoke-AgentRulesManualDirectorySetup -CurrentSettings $null) {
                    return $true
                }
            }
            '0' { return $false }
            default {
                Write-Host '[ERROR] 無效的選項，請輸入 0、1 或 2。' -ForegroundColor Red
                $null = Read-Host '按 Enter 繼續'
            }
        }
    }
}

function Show-AgentRulesMenu {
    if (-not (Initialize-AgentRulesDirectories)) {
        return
    }

    while ($true) {
        Write-AgentRulesMenuHeader
        Write-Host '1. 檢查狀態'
        Write-Host '2. 預覽同步'
        Write-Host '3. 同步全部'
        Write-Host '4. 僅同步 Codex'
        Write-Host '5. 僅同步 Antigravity'
        Write-Host '6. 執行測試'
        Write-Host '7. 預覽備份清理'
        Write-Host '8. 清理過期備份'
        Write-Host '9. 修改 Agent 目錄'
        Write-Host '10. 重新偵測 Agent 目錄'
        Write-Host '11. 回復備份檔案'
        Write-Host '0. 離開'
        Write-Host

        $selection = Read-Host '請選擇'
        if ($null -eq $selection) {
            return
        }
        $selection = $selection.Trim()
        $commandName = $null
        $commandArguments = @()
        switch ($selection) {
            '1' { $commandName = 'check' }
            '2' { $commandName = 'preview' }
            '3' {
                if (Confirm-AgentRulesSync -TargetDescription 'Codex 與 Antigravity') {
                    $commandName = 'sync'
                }
            }
            '4' {
                if (Confirm-AgentRulesSync -TargetDescription 'Codex') {
                    $commandName = 'codex'
                }
            }
            '5' {
                if (Confirm-AgentRulesSync -TargetDescription 'Antigravity') {
                    $commandName = 'antigravity'
                }
            }
            '6' { $commandName = 'test' }
            '7' { $commandName = 'cleanup' }
            '8' {
                Write-Host
                Write-Host '即將刪除符合保留政策的過期備份。' -ForegroundColor Yellow
                $confirmation = Read-Host '是否繼續？[y/N]'
                if (($null -ne $confirmation) -and ($confirmation.Trim() -ieq 'y')) {
                    $commandName = 'cleanup'
                    $commandArguments = @('--apply')
                }
            }
            '9' {
                $null = Invoke-AgentRulesManualDirectorySetup `
                    -CurrentSettings (Get-AgentRulesSettingsForMenu)
                $null = Read-Host '按 Enter 返回選單'
            }
            '10' {
                $null = Invoke-AgentRulesDirectoryDetection
                $null = Read-Host '按 Enter 返回選單'
            }
            '11' {
                Invoke-AgentRulesRestoreMenu
                Show-AgentRulesCommandResult -ExitCode $script:LastCommandExitCode
            }
            '0' { return }
            default {
                Write-Host
                Write-Host '[ERROR] 無效的選項，請輸入 0 到 11。' -ForegroundColor Red
                $null = Read-Host '按 Enter 返回選單'
            }
        }

        if ($null -ne $commandName) {
            Invoke-AgentRulesCommand -Name $commandName -Arguments $commandArguments
            Show-AgentRulesCommandResult -ExitCode $script:LastCommandExitCode
        }
    }
}

if ($Help) {
    Write-AgentRulesUsage
    exit 0
}

$unexpectedArguments = @(
    $ExtraArguments |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($unexpectedArguments.Count -gt 0 -and $Command -notin @('cleanup', 'restore')) {
    Write-Host "[ERROR] 不支援額外參數：$($unexpectedArguments -join ' ')" -ForegroundColor Red
    Write-Host
    Write-AgentRulesUsage
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    Show-AgentRulesMenu
    exit 0
}

$normalizedCommand = $Command.ToLowerInvariant()
if ($normalizedCommand -in @('help', '--help', '-h')) {
    Write-AgentRulesUsage
    exit 0
}

if ($normalizedCommand -notin @('check', 'preview', 'sync', 'codex', 'antigravity', 'build', 'test', 'cleanup', 'restore')) {
    Write-Host "[ERROR] 未知命令：$Command" -ForegroundColor Red
    Write-Host
    Write-AgentRulesUsage
    exit 2
}

Invoke-AgentRulesCommand -Name $normalizedCommand -Arguments $ExtraArguments
exit $script:LastCommandExitCode
