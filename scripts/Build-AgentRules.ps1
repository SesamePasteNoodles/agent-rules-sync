[CmdletBinding()]
param(
    [ValidateSet('Codex', 'Antigravity', 'All')]
    [string]$Target = 'All',

    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentRules.Common.ps1')

try {
    $context = Get-AgentRulesContext -ConfigPath $ConfigPath
    $targetNames = @(Get-SelectedTargetNames -Context $context -Target $Target)
    foreach ($targetName in $targetNames) {
        Write-AgentRulesLog -Level 'INFO' -Message "開始建置 $targetName"
        $null = Invoke-AgentRulesBuild -Context $context -TargetName $targetName
    }
    Write-AgentRulesLog -Level 'OK' -Message "建置完成：$($targetNames -join ', ')"
    Write-AgentRulesLog -Level 'SUMMARY' -Message '結論：建置產物已更新。下一步：執行 AgentRules.cmd preview 檢查預計部署的變更。'
    exit 0
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    Write-AgentRulesLog -Level 'SUMMARY' -Message '結論：建置失敗。下一步：先處理上方 [ERROR]，不要進行同步。'
    exit 2
}
