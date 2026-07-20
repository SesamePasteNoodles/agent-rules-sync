[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$BackupId,

    [ValidateSet('Codex', 'Antigravity', 'All')]
    [string]$Target = 'All',

    [switch]$Apply,

    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'AgentRules.Common.ps1')

function Test-StandardBackupId {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '^\d{8}-\d{6}-\d{3}$') {
        return $false
    }

    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        'yyyyMMdd-HHmmss-fff',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function Get-AvailableBackupSets {
    param([Parameter(Mandatory = $true)][string]$BackupRoot)

    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
        return @()
    }

    $sets = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $BackupRoot -Directory -Force)) {
        if (-not (Test-StandardBackupId -Value $directory.Name)) {
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
            $sets += [pscustomobject]@{
                BackupId = $directory.Name
                Targets = $targets
                FileCount = $fileCount
            }
        }
    }

    return @($sets | Sort-Object BackupId -Descending)
}

function Show-AvailableBackupSets {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $BackupSets
    )

    if ($BackupSets.Count -eq 0) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message '沒有可回復的標準時間戳備份。'
        return
    }

    Write-Host '可回復的備份（只包含當次同步前被覆寫的檔案）：'
    for ($index = 0; $index -lt $BackupSets.Count; $index++) {
        $set = $BackupSets[$index]
        Write-Host (
            '  {0}. {1}  {2}  {3} 個檔案' -f
            ($index + 1),
            $set.BackupId,
            ($set.Targets -join ', '),
            $set.FileCount
        )
    }
    Write-AgentRulesLog -Level 'SUMMARY' -Message "共 $($BackupSets.Count) 份備份；指定 BackupId 可預覽回復。"
}

function Get-BackupFilesWithoutReparsePoints {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    $rootItem = Get-Item -LiteralPath $TargetRoot -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "備份目標不可為重新解析點：$TargetRoot"
    }

    $files = @()
    $pending = New-Object System.Collections.Stack
    $pending.Push($rootItem)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory.FullName -Force)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "備份內容不可包含重新解析點：$($item.FullName)"
            }
            if ($item.PSIsContainer) {
                $pending.Push($item)
            }
            elseif (Test-Path -LiteralPath $item.FullName -PathType Leaf) {
                $files += $item
            }
            else {
                throw "備份內容不是一般檔案：$($item.FullName)"
            }
        }
    }

    return $files
}

function Assert-NoExistingReparsePointInPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $current = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "路徑不可包含重新解析點：$current"
            }
        }

        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent) {
            break
        }
        $current = $parent.FullName
    }
}

function Assert-RestoreDestinationState {
    param([Parameter(Mandatory = $true)]$PlanItem)

    Assert-NoExistingReparsePointInPath -Path $PlanItem.DestinationPath
    if ($PlanItem.DestinationExists) {
        if (-not (Test-Path -LiteralPath $PlanItem.DestinationPath -PathType Leaf)) {
            throw "目的檔案在預檢後消失或改變類型：$($PlanItem.DestinationPath)"
        }
        if ((Get-FileSha256 -LiteralPath $PlanItem.DestinationPath) -ne $PlanItem.DestinationHash) {
            throw "目的檔案在預檢後發生變更：$($PlanItem.DestinationPath)"
        }
    }
    elseif (Test-Path -LiteralPath $PlanItem.DestinationPath) {
        throw "目的檔案在預檢後出現，拒絕覆寫：$($PlanItem.DestinationPath)"
    }
}

function Get-RestorePlan {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$BackupRoot,
        [Parameter(Mandatory = $true)][string]$SelectedBackupId,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity', 'All')][string]$SelectedTarget
    )

    if (-not (Test-StandardBackupId -Value $SelectedBackupId)) {
        throw "BackupId 必須是 yyyyMMdd-HHmmss-fff 格式：$SelectedBackupId"
    }

    $backupSetRoot = Get-SafeChildPath -Root $BackupRoot -RelativePath $SelectedBackupId
    Assert-NoExistingReparsePointInPath -Path $BackupRoot
    if (-not (Test-Path -LiteralPath $backupSetRoot -PathType Container)) {
        throw "找不到備份：$SelectedBackupId"
    }
    $backupSetItem = Get-Item -LiteralPath $backupSetRoot -Force
    if (($backupSetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "備份目錄不可為重新解析點：$backupSetRoot"
    }

    $requestedTargets = if ($SelectedTarget -eq 'All') {
        @('Codex', 'Antigravity')
    }
    else {
        @($SelectedTarget)
    }

    $plan = @()
    $foundTargets = @()
    foreach ($targetName in $requestedTargets) {
        $targetConfiguration = Get-TargetConfiguration -Context $Context -TargetName $targetName
        $targetRoot = Get-SafeChildPath `
            -Root $backupSetRoot `
            -RelativePath $targetName.ToLowerInvariant()
        if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
            if ($SelectedTarget -ne 'All') {
                throw "備份 $SelectedBackupId 不包含 $targetName。"
            }
            continue
        }

        $foundTargets += $targetName
        $backupFiles = @(Get-BackupFilesWithoutReparsePoints -TargetRoot $targetRoot)
        if ($backupFiles.Count -eq 0) {
            throw "備份 $SelectedBackupId 的 $targetName 不包含任何檔案。"
        }

        foreach ($backupFile in $backupFiles) {
            $relativePath = $backupFile.FullName.Substring($targetRoot.Length).TrimStart('\', '/').Replace('\', '/')
            if ($relativePath -notin $targetConfiguration.ManagedFiles) {
                throw "備份包含目前未受管理的檔案，拒絕整份回復：$targetName/$relativePath"
            }

            $destinationPath = Get-SafeChildPath `
                -Root $targetConfiguration.DestinationRoot `
                -RelativePath $relativePath
            Assert-NoExistingReparsePointInPath -Path $destinationPath
            if (Test-Path -LiteralPath $destinationPath -PathType Container) {
                throw "目的檔案目前是目錄：$destinationPath"
            }

            $sourceHash = Get-FileSha256 -LiteralPath $backupFile.FullName
            $destinationExists = Test-Path -LiteralPath $destinationPath -PathType Leaf
            $destinationHash = if ($destinationExists) {
                Get-FileSha256 -LiteralPath $destinationPath
            }
            else {
                $null
            }
            $status = if (-not $destinationExists) {
                'Missing'
            }
            elseif ($sourceHash -eq $destinationHash) {
                'Unchanged'
            }
            else {
                'Modified'
            }

            $plan += [pscustomobject]@{
                TargetName = $targetName
                RelativePath = $relativePath
                SourcePath = $backupFile.FullName
                SourceHash = $sourceHash
                DestinationPath = $destinationPath
                DestinationExists = $destinationExists
                DestinationHash = $destinationHash
                Status = $status
                TemporaryPath = $null
                ProtectionPath = $null
                ProtectionRelativePath = $null
                Applied = $false
            }
        }
    }

    if ($foundTargets.Count -eq 0) {
        throw "備份 $SelectedBackupId 不包含可回復的目標。"
    }
    return $plan
}

function Show-RestorePlan {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$SelectedBackupId
    )

    foreach ($item in $Plan) {
        $level = if ($item.Status -eq 'Unchanged') { 'CHECK' } else { 'CHANGE' }
        $description = switch ($item.Status) {
            'Missing' { '將新增' }
            'Modified' { '將以備份覆寫' }
            default { '內容相同' }
        }
        Write-AgentRulesLog `
            -Level $level `
            -Message "$($item.TargetName) $($item.RelativePath)：$description → $($item.DestinationPath)"
    }

    $changeCount = @($Plan | Where-Object { $_.Status -ne 'Unchanged' }).Count
    Write-AgentRulesLog `
        -Level 'SUMMARY' `
        -Message "備份 $SelectedBackupId 預覽完成；$changeCount 個檔案需要回復，不會刪除其他檔案。"
}

function Publish-ProtectionBackup {
    param(
        [Parameter(Mandatory = $true)][string]$PendingRoot,
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )

    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $backupId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $publishedRoot = Join-Path $BackupRoot $backupId
        try {
            [System.IO.Directory]::Move($PendingRoot, $publishedRoot)
            return [pscustomobject]@{
                BackupId = $backupId
                Root = $publishedRoot
            }
        }
        catch [System.IO.IOException] {
            if (-not (Test-Path -LiteralPath $publishedRoot)) {
                throw
            }
            Start-Sleep -Milliseconds 2
        }
    }

    throw '無法為回復前保護備份取得唯一 BackupId。'
}

function Invoke-RestorePlan {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )

    $changes = @($Plan | Where-Object { $_.Status -ne 'Unchanged' })
    if ($changes.Count -eq 0) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message '目的檔案已與備份一致，不需要回復。'
        return
    }

    $protectionCount = @($changes | Where-Object { $_.DestinationExists }).Count
    $pendingProtectionRoot = $null
    $publishedProtectionRoot = $null
    $createdDestinationDirectories = @()
    $backupRootCreated = $false
    $mutationStarted = $false
    try {
        if ($protectionCount -gt 0) {
            Assert-NoExistingReparsePointInPath -Path $BackupRoot
            if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
                [System.IO.Directory]::CreateDirectory($BackupRoot) | Out-Null
                $backupRootCreated = $true
            }
            $pendingProtectionRoot = Join-Path `
                $BackupRoot `
                ('.restore-protection-' + [System.Guid]::NewGuid().ToString('N'))
            [System.IO.Directory]::CreateDirectory($pendingProtectionRoot) | Out-Null
        }

        foreach ($item in $changes) {
            $sourceItem = Get-Item -LiteralPath $item.SourcePath -Force
            if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "備份在預檢後變成重新解析點：$($item.SourcePath)"
            }
            if ((Get-FileSha256 -LiteralPath $item.SourcePath) -ne $item.SourceHash) {
                throw "備份在預檢後發生變更：$($item.SourcePath)"
            }

            Assert-RestoreDestinationState -PlanItem $item
            $destinationParent = Split-Path -Parent $item.DestinationPath
            $missingDirectory = $destinationParent
            while (-not (Test-Path -LiteralPath $missingDirectory)) {
                $createdDestinationDirectories += $missingDirectory
                $parent = [System.IO.Directory]::GetParent($missingDirectory)
                if ($null -eq $parent) {
                    break
                }
                $missingDirectory = $parent.FullName
            }
            [System.IO.Directory]::CreateDirectory($destinationParent) | Out-Null
            $item.TemporaryPath = $item.DestinationPath + '.restore-' + [System.Guid]::NewGuid().ToString('N')
            Copy-Item -LiteralPath $item.SourcePath -Destination $item.TemporaryPath
            if ((Get-FileSha256 -LiteralPath $item.TemporaryPath) -ne $item.SourceHash) {
                throw "回復暫存檔 SHA-256 不一致：$($item.TemporaryPath)"
            }

            if ($item.DestinationExists) {
                $item.ProtectionRelativePath = '{0}/{1}' -f `
                    $item.TargetName.ToLowerInvariant(), `
                    $item.RelativePath
                $item.ProtectionPath = Get-SafeChildPath `
                    -Root $pendingProtectionRoot `
                    -RelativePath $item.ProtectionRelativePath
                [System.IO.Directory]::CreateDirectory((Split-Path -Parent $item.ProtectionPath)) | Out-Null
                Copy-Item -LiteralPath $item.DestinationPath -Destination $item.ProtectionPath
                if ((Get-FileSha256 -LiteralPath $item.ProtectionPath) -ne $item.DestinationHash) {
                    throw "回復前保護備份 SHA-256 不一致：$($item.ProtectionPath)"
                }
            }
        }

        foreach ($item in $changes) {
            Assert-RestoreDestinationState -PlanItem $item
        }
        if ($protectionCount -gt 0) {
            $publishedProtection = Publish-ProtectionBackup `
                -PendingRoot $pendingProtectionRoot `
                -BackupRoot $BackupRoot
            $publishedProtectionRoot = $publishedProtection.Root
            $pendingProtectionRoot = $null
            foreach ($item in @($changes | Where-Object { $_.DestinationExists })) {
                $item.ProtectionPath = Get-SafeChildPath `
                    -Root $publishedProtectionRoot `
                    -RelativePath $item.ProtectionRelativePath
            }
        }

        $mutationStarted = $true
        foreach ($item in $changes) {
            Assert-RestoreDestinationState -PlanItem $item
            Move-Item -LiteralPath $item.TemporaryPath -Destination $item.DestinationPath -Force
            $item.TemporaryPath = $null
            $item.Applied = $true
            if ((Get-FileSha256 -LiteralPath $item.DestinationPath) -ne $item.SourceHash) {
                throw "回復後 SHA-256 不一致：$($item.DestinationPath)"
            }
            Write-AgentRulesLog -Level 'OK' -Message "$($item.TargetName) $($item.RelativePath)：回復完成"
        }

        $protectionMessage = if ($protectionCount -gt 0) {
            "；$protectionCount 個既有檔案的回復前內容保留於 $publishedProtectionRoot。"
        }
        else {
            '；目的檔案原先均不存在，因此沒有需要保存的回復前內容。'
        }
        Write-AgentRulesLog `
            -Level 'SUMMARY' `
            -Message "已回復 $($changes.Count) 個檔案$protectionMessage"
    }
    catch {
        $restoreError = $_.Exception.Message
        $rollbackErrors = @()
        foreach ($item in $changes) {
            try {
                if (($null -ne $item.TemporaryPath) -and
                    (Test-Path -LiteralPath $item.TemporaryPath -PathType Leaf)) {
                    Remove-Item -LiteralPath $item.TemporaryPath -Force
                }
            }
            catch {
                $rollbackErrors += "$($item.TemporaryPath)：暫存檔清理失敗：$($_.Exception.Message)"
            }
        }

        if ($mutationStarted) {
            Write-AgentRulesLog -Level 'ERROR' -Message "回復失敗，開始回滾整次操作：$restoreError"
            foreach ($item in @($changes | Where-Object { $_.Applied })) {
                try {
                    if ($item.DestinationExists) {
                        if (($null -eq $item.ProtectionPath) -or
                            (-not (Test-Path -LiteralPath $item.ProtectionPath -PathType Leaf))) {
                            throw "缺少回復前保護檔：$($item.DestinationPath)"
                        }
                        $rollbackTemporaryPath = $item.DestinationPath + '.rollback-' +
                            [System.Guid]::NewGuid().ToString('N')
                        Copy-Item -LiteralPath $item.ProtectionPath -Destination $rollbackTemporaryPath
                        Move-Item -LiteralPath $rollbackTemporaryPath -Destination $item.DestinationPath -Force
                        if ((Get-FileSha256 -LiteralPath $item.DestinationPath) -ne $item.DestinationHash) {
                            throw "回滾後 SHA-256 不一致：$($item.DestinationPath)"
                        }
                    }
                    elseif (Test-Path -LiteralPath $item.DestinationPath -PathType Leaf) {
                        Remove-Item -LiteralPath $item.DestinationPath -Force
                    }
                }
                catch {
                    $rollbackErrors += "$($item.DestinationPath)：$($_.Exception.Message)"
                }
            }
        }

        if (($null -ne $pendingProtectionRoot) -and
            (Test-Path -LiteralPath $pendingProtectionRoot -PathType Container)) {
            try {
                Remove-Item -LiteralPath $pendingProtectionRoot -Recurse -Force
            }
            catch {
                $rollbackErrors += "$pendingProtectionRoot：未完成保護備份清理失敗：$($_.Exception.Message)"
            }
        }

        foreach ($directory in @(
            $createdDestinationDirectories |
                Sort-Object Length -Descending |
                Select-Object -Unique
        )) {
            try {
                if ((Test-Path -LiteralPath $directory -PathType Container) -and
                    (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0)) {
                    Remove-Item -LiteralPath $directory -Force
                }
            }
            catch {
                $rollbackErrors += "$directory：新建目錄清理失敗：$($_.Exception.Message)"
            }
        }
        if ($backupRootCreated) {
            try {
                if ((Test-Path -LiteralPath $BackupRoot -PathType Container) -and
                    (@(Get-ChildItem -LiteralPath $BackupRoot -Force).Count -eq 0)) {
                    Remove-Item -LiteralPath $BackupRoot -Force
                }
            }
            catch {
                $rollbackErrors += "$BackupRoot：空備份根目錄清理失敗：$($_.Exception.Message)"
            }
        }

        if ($rollbackErrors.Count -gt 0) {
            throw "$restoreError；另有回滾失敗：$($rollbackErrors -join '；')"
        }
        throw $restoreError
    }
}

try {
    $context = Get-AgentRulesContext -ConfigPath $ConfigPath
    $backupRoot = [System.IO.Path]::GetFullPath((Join-Path $context.RepositoryRoot 'backups'))

    if ([string]::IsNullOrWhiteSpace($BackupId)) {
        if ($Apply) {
            throw '-Apply 必須搭配 BackupId。'
        }
        $availableBackups = @(Get-AvailableBackupSets -BackupRoot $backupRoot)
        Show-AvailableBackupSets -BackupSets $availableBackups
        exit 0
    }

    $restorePlan = @(
        Get-RestorePlan `
            -Context $context `
            -BackupRoot $backupRoot `
            -SelectedBackupId $BackupId `
            -SelectedTarget $Target
    )
    Show-RestorePlan -Plan $restorePlan -SelectedBackupId $BackupId
    if (-not $Apply) {
        exit 0
    }

    Invoke-RestorePlan -Plan $restorePlan -BackupRoot $backupRoot
    exit 0
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 2
}
