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
    Write-Host '  AgentRules.cmd help'
    Write-Host
    Write-Host '注意：sync、codex 與 antigravity 會立即套用變更。' -ForegroundColor Yellow
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
        return 2
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments | Out-Host
    return $LASTEXITCODE
}

function Invoke-AgentRulesCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('check', 'preview', 'sync', 'codex', 'antigravity', 'build', 'test')]
        [string]$Name
    )

    switch ($Name) {
        'check' {
            return Invoke-AgentRulesChildScript -RelativePath 'scripts\Check-AgentRules.ps1' -Arguments @('-Target', 'All')
        }
        'preview' {
            return Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'All')
        }
        'sync' {
            return Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'All', '-Apply')
        }
        'codex' {
            return Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'Codex', '-Apply')
        }
        'antigravity' {
            return Invoke-AgentRulesChildScript -RelativePath 'scripts\Sync-AgentRules.ps1' -Arguments @('-Target', 'Antigravity', '-Apply')
        }
        'build' {
            return Invoke-AgentRulesChildScript -RelativePath 'scripts\Build-AgentRules.ps1' -Arguments @('-Target', 'All')
        }
        'test' {
            return Invoke-AgentRulesChildScript -RelativePath 'tests\Test-AgentRules.ps1'
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

function Show-AgentRulesMenu {
    while ($true) {
        Write-AgentRulesMenuHeader
        Write-Host '1. 檢查狀態'
        Write-Host '2. 預覽同步'
        Write-Host '3. 同步全部'
        Write-Host '4. 僅同步 Codex'
        Write-Host '5. 僅同步 Antigravity'
        Write-Host '6. 執行測試'
        Write-Host '0. 離開'
        Write-Host

        $selection = Read-Host '請選擇'
        if ($null -eq $selection) {
            return 0
        }
        $selection = $selection.Trim()
        $commandName = $null
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
            '0' { return 0 }
            default {
                Write-Host
                Write-Host '[ERROR] 無效的選項，請輸入 0 到 6。' -ForegroundColor Red
                $null = Read-Host '按 Enter 返回選單'
            }
        }

        if ($null -ne $commandName) {
            $exitCode = Invoke-AgentRulesCommand -Name $commandName
            Show-AgentRulesCommandResult -ExitCode $exitCode
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
if ($unexpectedArguments.Count -gt 0) {
    Write-Host "[ERROR] 不支援額外參數：$($unexpectedArguments -join ' ')" -ForegroundColor Red
    Write-Host
    Write-AgentRulesUsage
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    exit (Show-AgentRulesMenu)
}

$normalizedCommand = $Command.ToLowerInvariant()
if ($normalizedCommand -in @('help', '--help', '-h')) {
    Write-AgentRulesUsage
    exit 0
}

if ($normalizedCommand -notin @('check', 'preview', 'sync', 'codex', 'antigravity', 'build', 'test')) {
    Write-Host "[ERROR] 未知命令：$Command" -ForegroundColor Red
    Write-Host
    Write-AgentRulesUsage
    exit 2
}

exit (Invoke-AgentRulesCommand -Name $normalizedCommand)
