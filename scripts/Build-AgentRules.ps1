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
    exit 0
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 2
}
