[CmdletBinding()]
param(
    [ValidateSet('Codex', 'Antigravity', 'All')]
    [string]$Target = 'All',

    [switch]$Apply,

    [switch]$NoBackup,

    [switch]$Force,

    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentRules.Common.ps1')

function Invoke-TargetSync {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$TargetName,
        [Parameter(Mandatory = $true)]$Artifacts,
        [Parameter(Mandatory = $true)]$TargetConfiguration,
        [Parameter(Mandatory = $true)][bool]$ShouldApply,
        [Parameter(Mandatory = $true)][bool]$ShouldBackup,
        [Parameter(Mandatory = $true)][bool]$AllowForce
    )

    $comparison = @(Get-ArtifactComparison -Artifacts $Artifacts -Root $TargetConfiguration.DestinationRoot)
    $changes = @($comparison | Where-Object { $_.Status -ne 'Unchanged' })
    foreach ($result in $comparison) {
        $level = if ($result.Status -eq 'Unchanged') { 'CHECK' } else { 'CHANGE' }
        $description = switch ($result.Status) {
            'Missing' { '將新增' }
            'Modified' { '將更新' }
            default { '無變更' }
        }
        Write-AgentRulesLog -Level $level -Message "$TargetName $($result.RelativePath)：$description"
    }

    if ($changes.Count -eq 0) {
        Write-AgentRulesLog -Level 'OK' -Message "$TargetName 無需同步。"
        return
    }
    if (-not $ShouldApply) {
        Write-AgentRulesLog -Level 'INFO' -Message "$TargetName 為預覽模式；未修改目的地。"
        return
    }

    if (-not $ShouldBackup -and -not $AllowForce) {
        Write-AgentRulesLog -Level 'WARN' -Message "$TargetName 已明確停用備份；若部署失敗，只能回復本次已存在於目的地的暫存副本。"
    }

    [System.IO.Directory]::CreateDirectory($TargetConfiguration.DestinationRoot) | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupRoot = Join-Path (Join-Path (Join-Path $Context.RepositoryRoot 'backups') $timestamp) $TargetName.ToLowerInvariant()
    $staged = @()
    $backupMap = @{}
    $newFiles = @()

    try {
        foreach ($change in $changes) {
            $artifact = @($Artifacts | Where-Object { $_.RelativePath -eq $change.RelativePath })[0]
            $destinationPath = $change.FullPath
            $destinationDirectory = Split-Path -Parent $destinationPath
            [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
            $temporaryPath = $destinationPath + '.tmp-' + [System.Guid]::NewGuid().ToString('N')
            Write-Utf8NoBomText -LiteralPath $temporaryPath -Content $artifact.Content
            if ((Get-FileSha256 -LiteralPath $temporaryPath) -ne $artifact.Hash) {
                throw "暫存檔 SHA-256 不一致：$temporaryPath"
            }
            $staged += [pscustomobject]@{
                RelativePath = $change.RelativePath
                TemporaryPath = $temporaryPath
                DestinationPath = $destinationPath
                ExpectedHash = $artifact.Hash
            }
        }

        foreach ($item in $staged) {
            if (Test-Path -LiteralPath $item.DestinationPath -PathType Leaf) {
                if ($ShouldBackup) {
                    $backupPath = Get-SafeChildPath -Root $backupRoot -RelativePath $item.RelativePath
                    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $backupPath)) | Out-Null
                    Copy-Item -LiteralPath $item.DestinationPath -Destination $backupPath -Force
                    if ((Get-FileSha256 -LiteralPath $backupPath) -ne (Get-FileSha256 -LiteralPath $item.DestinationPath)) {
                        throw "備份 SHA-256 不一致：$backupPath"
                    }
                    $backupMap[$item.DestinationPath] = $backupPath
                    Write-AgentRulesLog -Level 'BACKUP' -Message "$TargetName $($item.RelativePath) → $backupPath"
                }
                else {
                    $rollbackPath = $item.DestinationPath + '.rollback-' + [System.Guid]::NewGuid().ToString('N')
                    Copy-Item -LiteralPath $item.DestinationPath -Destination $rollbackPath -Force
                    $backupMap[$item.DestinationPath] = $rollbackPath
                }
            }
            else {
                $newFiles += $item.DestinationPath
            }
        }

        foreach ($item in $staged) {
            Move-Item -LiteralPath $item.TemporaryPath -Destination $item.DestinationPath -Force
            if ((Get-FileSha256 -LiteralPath $item.DestinationPath) -ne $item.ExpectedHash) {
                throw "部署後 SHA-256 不一致：$($item.DestinationPath)"
            }
            Write-AgentRulesLog -Level 'OK' -Message "$TargetName $($item.RelativePath)：SHA-256 一致"
        }

        if (-not $ShouldBackup) {
            foreach ($rollbackPath in $backupMap.Values) {
                Remove-Item -LiteralPath $rollbackPath -Force
            }
        }
        Write-AgentRulesLog -Level 'OK' -Message "$TargetName 同步完成，共 $($changes.Count) 個檔案。"
    }
    catch {
        Write-AgentRulesLog -Level 'ERROR' -Message "$TargetName 同步失敗，開始回復：$($_.Exception.Message)"
        foreach ($item in $staged) {
            if (Test-Path -LiteralPath $item.TemporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $item.TemporaryPath -Force
            }
        }
        foreach ($destinationPath in $backupMap.Keys) {
            Copy-Item -LiteralPath $backupMap[$destinationPath] -Destination $destinationPath -Force
        }
        foreach ($newFile in $newFiles) {
            if (Test-Path -LiteralPath $newFile -PathType Leaf) {
                Remove-Item -LiteralPath $newFile -Force
            }
        }
        throw
    }
}

try {
    $context = Get-AgentRulesContext -ConfigPath $ConfigPath
    $targetNames = @(Get-SelectedTargetNames -Context $context -Target $Target)
    if ($NoBackup -and -not $Apply) {
        Write-AgentRulesLog -Level 'WARN' -Message '-NoBackup 在預覽模式不會產生作用。'
    }
    if ($Force) {
        Write-AgentRulesLog -Level 'INFO' -Message '-Force 已啟用；第一階段仍不會越過白名單或來源完整性檢查。'
    }

    foreach ($targetName in $targetNames) {
        Write-AgentRulesLog -Level 'INFO' -Message "建置 $targetName"
        $artifacts = @(Invoke-AgentRulesBuild -Context $context -TargetName $targetName)
        $targetConfiguration = Get-TargetConfiguration -Context $context -TargetName $targetName
        Invoke-TargetSync `
            -Context $context `
            -TargetName $targetName `
            -Artifacts $artifacts `
            -TargetConfiguration $targetConfiguration `
            -ShouldApply $Apply.IsPresent `
            -ShouldBackup (-not $NoBackup.IsPresent) `
            -AllowForce $Force.IsPresent
    }

    if (-not $Apply) {
        Write-AgentRulesLog -Level 'INFO' -Message '預覽完成；使用 -Apply 才會修改目的地。'
    }
    exit 0
}
catch [System.UnauthorizedAccessException] {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 3
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 2
}
