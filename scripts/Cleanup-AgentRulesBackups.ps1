[CmdletBinding()]
param(
    [switch]$Apply,

    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 30,

    [ValidateRange(1, 1000)]
    [int]$KeepLatest = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'AgentRules.Common.ps1')

try {
    $repositoryRoot = Get-AgentRulesRepositoryRoot
    $backupRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'backups'))
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message '沒有備份目錄，不需要清理。'
        exit 0
    }

    $timestampFormat = 'yyyyMMdd-HHmmss-fff'
    $timestampPattern = '^\d{8}-\d{6}-\d{3}$'
    $recognized = @()
    $ignored = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force)) {
        $timestamp = [datetime]::MinValue
        $validTimestamp = $directory.Name -match $timestampPattern -and
            [datetime]::TryParseExact(
                $directory.Name,
                $timestampFormat,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$timestamp
            )
        if ($validTimestamp) {
            $recognized += [pscustomobject]@{
                Directory = $directory
                Timestamp = $timestamp
            }
        }
        else {
            $ignored += $directory
        }
    }

    foreach ($directory in $ignored) {
        Write-AgentRulesLog -Level 'WARN' -Message "略過非標準備份目錄：$($directory.FullName)"
    }

    $sorted = @($recognized | Sort-Object Timestamp -Descending)
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $candidates = @(
        $sorted |
            Select-Object -Skip $KeepLatest |
            Where-Object { $_.Timestamp -lt $cutoff }
    )

    if ($candidates.Count -eq 0) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message (
            "沒有符合清理條件的備份；保留最新 $KeepLatest 份，保留天數 $RetentionDays 天。"
        )
        exit 0
    }

    $candidateFiles = @(
        foreach ($candidate in $candidates) {
            Get-ChildItem -LiteralPath $candidate.Directory.FullName -Recurse -File -Force
        }
    )
    $candidateBytes = ($candidateFiles | Measure-Object Length -Sum).Sum
    if ($null -eq $candidateBytes) {
        $candidateBytes = 0
    }

    foreach ($candidate in $candidates) {
        Write-AgentRulesLog -Level 'CHANGE' -Message (
            "{0}：{1}" -f
            ($(if ($Apply) { '將刪除' } else { '預計刪除' })),
            $candidate.Directory.FullName
        )
    }

    if (-not $Apply) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message (
            "預覽完成；將清理 $($candidates.Count) 個備份目錄、$($candidateFiles.Count) 個檔案、$candidateBytes bytes。" +
            ' 使用 cleanup --apply 才會實際刪除。'
        )
        exit 0
    }

    $backupPrefix = $backupRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($candidate in $candidates) {
        $resolvedPath = [System.IO.Path]::GetFullPath($candidate.Directory.FullName)
        if (-not $resolvedPath.StartsWith($backupPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "拒絕刪除超出備份根目錄的路徑：$resolvedPath"
        }
        if ((Split-Path -Leaf $resolvedPath) -notmatch $timestampPattern) {
            throw "拒絕刪除非標準備份目錄：$resolvedPath"
        }
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
        Write-AgentRulesLog -Level 'OK' -Message "已刪除備份：$resolvedPath"
    }

    Write-AgentRulesLog -Level 'SUMMARY' -Message (
        "清理完成；已刪除 $($candidates.Count) 個備份目錄、$($candidateFiles.Count) 個檔案、$candidateBytes bytes。"
    )
    exit 0
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 2
}
