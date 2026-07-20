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
                Write-AgentRulesLog -Level 'WARN' -Message "$targetName $($result.RelativePath)：$($result.Status)"
            }
        }
    }
}
catch [System.UnauthorizedAccessException] {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 3
}
catch {
    Write-AgentRulesLog -Level 'ERROR' -Message $_.Exception.Message
    exit 2
}

if ($hasDifference) {
    Write-AgentRulesLog -Level 'WARN' -Message '存在尚未建置或尚未部署的差異。'
    exit 1
}

Write-AgentRulesLog -Level 'OK' -Message '來源、dist 與目的地全部一致。'
exit 0
