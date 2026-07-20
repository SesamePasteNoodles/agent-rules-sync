[CmdletBinding()]
param(
    [ValidateSet('Codex', 'Antigravity', 'All')]
    [string]$Target = 'All',

    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentRules.Common.ps1')

$hasDifference = $false
$distDifferenceCount = 0
$destinationDifferenceCount = 0

try {
    $context = Get-AgentRulesContext -ConfigPath $ConfigPath
    $targetNames = @(Get-SelectedTargetNames -Context $context -Target $Target)

    foreach ($targetName in $targetNames) {
        $targetConfiguration = Get-TargetConfiguration -Context $context -TargetName $targetName
        $artifacts = @(Get-AgentRulesArtifacts -Context $context -TargetName $targetName)
        Assert-ArtifactWhitelist -TargetConfiguration $targetConfiguration -Artifacts $artifacts

        if (($targetName -eq 'Antigravity') -and ($targetConfiguration.MaxCharacters -gt 0)) {
            $length = $artifacts[0].Content.Length
            if ($length -gt $targetConfiguration.MaxCharacters) {
                throw "Antigravity GEMINI.md 共 $length 字元，超過限制 $($targetConfiguration.MaxCharacters)。"
            }
            Write-AgentRulesLog -Level 'CHECK' -Message "Antigravity GEMINI.md：$length / $($targetConfiguration.MaxCharacters) 字元"
        }

        $distRoot = Get-DistRoot -Context $context -TargetName $targetName
        $distResults = @(Get-ArtifactComparison -Artifacts $artifacts -Root $distRoot)
        foreach ($result in $distResults) {
            if ($result.Status -eq 'Unchanged') {
                Write-AgentRulesLog -Level 'CHECK' -Message "$targetName dist/$($result.RelativePath)：一致"
            }
            else {
                $hasDifference = $true
                $distDifferenceCount++
                Write-AgentRulesLog -Level 'WARN' -Message "$targetName dist/$($result.RelativePath)：$($result.Status)"
            }
        }

        $destinationResults = @(Get-ArtifactComparison -Artifacts $artifacts -Root $targetConfiguration.DestinationRoot)
        foreach ($result in $destinationResults) {
            if ($result.Status -eq 'Unchanged') {
                Write-AgentRulesLog -Level 'CHECK' -Message "$targetName $($result.RelativePath)：一致"
            }
            else {
                $hasDifference = $true
                $destinationDifferenceCount++
                Write-AgentRulesLog -Level 'WARN' -Message "$targetName $($result.RelativePath)：$($result.Status)"
            }
        }
    }
}
catch [System.UnauthorizedAccessException] {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    Write-AgentRulesLog -Level 'SUMMARY' -Message '結論：無法存取目的地。下一步：確認路徑與權限後重新檢查。'
    exit 3
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    Write-AgentRulesLog -Level 'SUMMARY' -Message '結論：檢查失敗。下一步：先處理上方 [ERROR]，不要進行同步。'
    exit 2
}

if ($hasDifference) {
    Write-AgentRulesLog -Level 'WARN' -Message '存在尚未建置或尚未部署的差異。'
    if ($distDifferenceCount -gt 0) {
        Write-AgentRulesLog -Level 'SUMMARY' -Message (
            "結論：dist 有 $distDifferenceCount 個差異，目的地有 $destinationDifferenceCount 個差異。" +
            '下一步：先執行 AgentRules.cmd build，再執行 AgentRules.cmd preview。'
        )
    }
    else {
        Write-AgentRulesLog -Level 'SUMMARY' -Message (
            "結論：建置產物正常，但有 $destinationDifferenceCount 個檔案尚未同步。" +
            '下一步：先選 2 預覽，確認後選 3 同步全部。'
        )
    }
    exit 1
}

Write-AgentRulesLog -Level 'OK' -Message '來源、dist 與目的地全部一致。'
Write-AgentRulesLog -Level 'SUMMARY' -Message '結論：所有規則均為最新版本，不需要同步。下一步：可安全離開。'
exit 0
