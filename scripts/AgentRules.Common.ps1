Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GeneratedWarning = @'
<!--
此檔案由同步系統自動產生。
請勿直接修改，來源位於 AI Agent 規範專案。
-->
'@

$script:RuleDefinitions = @(
    [pscustomobject]@{ File = 'development.md'; Title = '程式開發規則' }
    [pscustomobject]@{ File = 'documents.md'; Title = '文件處理規則' }
    [pscustomobject]@{ File = 'terminal.md'; Title = '命令執行規則' }
    [pscustomobject]@{ File = 'git.md'; Title = 'Git 與版本控制規則' }
    [pscustomobject]@{ File = 'security.md'; Title = '安全性規則' }
    [pscustomobject]@{ File = 'testing.md'; Title = '測試與驗證規則' }
)

function Write-AgentRulesLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'CHECK', 'CHANGE', 'BACKUP', 'OK', 'WARN', 'ERROR', 'SUMMARY')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ('[{0}] {1}' -f $Level, $Message)
}

function Get-AgentRulesRepositoryRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

function Resolve-AgentRulesConfigPath {
    param([string]$ConfigPath)

    $repositoryRoot = Get-AgentRulesRepositoryRoot
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return Join-Path $repositoryRoot 'config\targets.json'
    }

    if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        return [System.IO.Path]::GetFullPath($ConfigPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ConfigPath))
}

function ConvertTo-NormalizedMarkdown {
    param([Parameter(Mandatory = $true)][string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    return $normalized.Trim() + "`n"
}

function Read-Utf8Text {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "必要檔案不存在：$LiteralPath"
    }

    return [System.IO.File]::ReadAllText($LiteralPath, [System.Text.Encoding]::UTF8)
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $LiteralPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Content, $encoding)
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Content)

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($Content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash
}

function Test-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return $false
    }

    $segments = $RelativePath -split '[\\/]'
    return -not ($segments -contains '..') -and -not ($segments -contains '.')
}

function Get-AgentRulesContext {
    param([string]$ConfigPath)

    $repositoryRoot = Get-AgentRulesRepositoryRoot
    $resolvedConfigPath = Resolve-AgentRulesConfigPath -ConfigPath $ConfigPath
    if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
        throw "設定檔不存在：$resolvedConfigPath"
    }

    try {
        $config = (Read-Utf8Text -LiteralPath $resolvedConfigPath) | ConvertFrom-Json
    }
    catch {
        throw "設定檔無法解析：$resolvedConfigPath。$($_.Exception.Message)"
    }

    if ($null -eq $config.targets) {
        throw '設定檔缺少 targets。'
    }

    return [pscustomobject]@{
        RepositoryRoot = $repositoryRoot
        ConfigPath = $resolvedConfigPath
        Config = $config
    }
}

function Get-SelectedTargetNames {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity', 'All')][string]$Target
    )

    $requested = if ($Target -eq 'All') { @('Codex', 'Antigravity') } else { @($Target) }
    $selected = @()
    foreach ($name in $requested) {
        $property = $Context.Config.targets.PSObject.Properties[$name]
        if ($null -eq $property) {
            throw "設定檔缺少目標：$name"
        }
        if ($property.Value.enabled -eq $true) {
            $selected += $name
        }
    }

    if ($selected.Count -eq 0) {
        throw '沒有啟用的同步目標。'
    }
    return $selected
}

function Get-ExpectedManagedFiles {
    param([Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity')][string]$TargetName)

    if ($TargetName -eq 'Codex') {
        return @(
            'AGENTS.md',
            'rules/development.md',
            'rules/documents.md',
            'rules/git.md',
            'rules/security.md',
            'rules/terminal.md',
            'rules/testing.md'
        )
    }
    return @('GEMINI.md')
}

function Get-TargetConfiguration {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity')][string]$TargetName
    )

    $targetConfig = $Context.Config.targets.PSObject.Properties[$TargetName].Value
    $expectedMode = if ($TargetName -eq 'Codex') { 'modular' } else { 'single-file' }
    if ($targetConfig.outputMode -ne $expectedMode) {
        throw "$TargetName 的 outputMode 必須是 $expectedMode。"
    }

    $configuredFiles = @($targetConfig.managedFiles | ForEach-Object { ([string]$_).Replace('\', '/') })
    $expectedFiles = @(Get-ExpectedManagedFiles -TargetName $TargetName)
    $managedFileDifferences = @(Compare-Object -ReferenceObject $expectedFiles -DifferenceObject $configuredFiles)
    if (($configuredFiles.Count -ne $expectedFiles.Count) -or ($managedFileDifferences.Count -ne 0)) {
        throw "$TargetName 的 managedFiles 不符合第一階段白名單。"
    }

    foreach ($relativePath in $configuredFiles) {
        if (-not (Test-SafeRelativePath -RelativePath $relativePath)) {
            throw "$TargetName 包含不安全的管理路徑：$relativePath"
        }
    }

    $expandedDestination = [System.Environment]::ExpandEnvironmentVariables([string]$targetConfig.destination)
    if ([string]::IsNullOrWhiteSpace($expandedDestination)) {
        throw "$TargetName 的 destination 不可為空。"
    }
    $destinationRoot = [System.IO.Path]::GetFullPath($expandedDestination)
    if (Test-Path -LiteralPath $destinationRoot -PathType Leaf) {
        throw "$TargetName 的 destination 預期為目錄，但目前是檔案：$destinationRoot"
    }

    return [pscustomobject]@{
        Name = $TargetName
        OutputMode = [string]$targetConfig.outputMode
        DestinationRoot = $destinationRoot
        ManagedFiles = $configuredFiles
        MaxCharacters = if ($null -ne $targetConfig.PSObject.Properties['maxCharacters']) {
            [int]$targetConfig.maxCharacters
        }
        else {
            0
        }
    }
}

function Remove-FirstMarkdownHeading {
    param([Parameter(Mandatory = $true)][string]$Content)

    $normalized = ConvertTo-NormalizedMarkdown -Content $Content
    return ($normalized -replace '^\s*#\s+[^\n]+\n+', '').Trim()
}

function Get-AgentRulesArtifacts {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity')][string]$TargetName
    )

    $sourceRoot = Join-Path $Context.RepositoryRoot 'src'
    $targetsRoot = Join-Path $Context.RepositoryRoot 'targets'
    $core = ConvertTo-NormalizedMarkdown -Content (Read-Utf8Text -LiteralPath (Join-Path $sourceRoot 'core.md'))
    $headerName = if ($TargetName -eq 'Codex') { 'codex-header.md' } else { 'antigravity-header.md' }
    $header = ConvertTo-NormalizedMarkdown -Content (Read-Utf8Text -LiteralPath (Join-Path $targetsRoot $headerName))
    $warning = ConvertTo-NormalizedMarkdown -Content $script:GeneratedWarning
    $artifacts = @()

    foreach ($definition in $script:RuleDefinitions) {
        $sourcePath = Join-Path (Join-Path $sourceRoot 'rules') $definition.File
        $null = Read-Utf8Text -LiteralPath $sourcePath
    }

    if ($TargetName -eq 'Codex') {
        $entryContent = $warning + "`n" + $header + "`n" + $core
        $artifacts += [pscustomobject]@{
            RelativePath = 'AGENTS.md'
            Content = $entryContent
            Hash = Get-TextSha256 -Content $entryContent
        }

        foreach ($definition in $script:RuleDefinitions) {
            $ruleContent = ConvertTo-NormalizedMarkdown -Content (
                Read-Utf8Text -LiteralPath (Join-Path (Join-Path $sourceRoot 'rules') $definition.File)
            )
            $outputContent = $warning + "`n" + $ruleContent
            $relativePath = 'rules/{0}' -f $definition.File
            $artifacts += [pscustomobject]@{
                RelativePath = $relativePath
                Content = $outputContent
                Hash = Get-TextSha256 -Content $outputContent
            }
        }
        return $artifacts
    }

    $sections = @(
        [pscustomobject]@{ Title = 'Antigravity 專屬規則'; Content = Remove-FirstMarkdownHeading -Content $header }
        [pscustomobject]@{ Title = '共用核心規範'; Content = Remove-FirstMarkdownHeading -Content $core }
    )
    foreach ($definition in $script:RuleDefinitions) {
        $sourceContent = Read-Utf8Text -LiteralPath (Join-Path (Join-Path $sourceRoot 'rules') $definition.File)
        $sections += [pscustomobject]@{
            Title = $definition.Title
            Content = Remove-FirstMarkdownHeading -Content $sourceContent
        }
    }

    $parts = @($warning.Trim())
    foreach ($section in $sections) {
        $parts += ('# {0}' -f $section.Title)
        $parts += $section.Content
    }
    $geminiContent = ($parts -join "`n`n").Trim() + "`n"
    $artifacts += [pscustomobject]@{
        RelativePath = 'GEMINI.md'
        Content = $geminiContent
        Hash = Get-TextSha256 -Content $geminiContent
    }
    return $artifacts
}

function Assert-ArtifactWhitelist {
    param(
        [Parameter(Mandatory = $true)]$TargetConfiguration,
        [Parameter(Mandatory = $true)]$Artifacts
    )

    $artifactPaths = @($Artifacts | ForEach-Object { $_.RelativePath })
    $artifactDifferences = @(
        Compare-Object -ReferenceObject $TargetConfiguration.ManagedFiles -DifferenceObject $artifactPaths
    )
    if (($artifactPaths.Count -ne $TargetConfiguration.ManagedFiles.Count) -or
        ($artifactDifferences.Count -ne 0)) {
        throw "$($TargetConfiguration.Name) 的建置產物超出或缺少白名單檔案。"
    }
}

function Get-DistRoot {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity')][string]$TargetName
    )

    return Join-Path (Join-Path $Context.RepositoryRoot 'dist') $TargetName.ToLowerInvariant()
}

function Get-SafeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (-not (Test-SafeRelativePath -RelativePath $RelativePath)) {
        throw "不安全的相對路徑：$RelativePath"
    }

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $fullRoot ($RelativePath -replace '/', '\')))
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "路徑超出允許的根目錄：$RelativePath"
    }
    return $fullPath
}

function Invoke-AgentRulesBuild {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity')][string]$TargetName
    )

    $targetConfiguration = Get-TargetConfiguration -Context $Context -TargetName $TargetName
    $artifacts = @(Get-AgentRulesArtifacts -Context $Context -TargetName $TargetName)
    Assert-ArtifactWhitelist -TargetConfiguration $targetConfiguration -Artifacts $artifacts
    $distRoot = Get-DistRoot -Context $Context -TargetName $TargetName

    foreach ($artifact in $artifacts) {
        $outputPath = Get-SafeChildPath -Root $distRoot -RelativePath $artifact.RelativePath
        Write-Utf8NoBomText -LiteralPath $outputPath -Content $artifact.Content
        $actualHash = Get-FileSha256 -LiteralPath $outputPath
        if ($actualHash -ne $artifact.Hash) {
            throw "建置後 SHA-256 不一致：$outputPath"
        }
        Write-AgentRulesLog -Level 'OK' -Message ("已建立 {0}（SHA-256: {1}）" -f $outputPath, $actualHash)
    }

    if (($TargetName -eq 'Antigravity') -and ($targetConfiguration.MaxCharacters -gt 0)) {
        $length = $artifacts[0].Content.Length
        if ($length -gt $targetConfiguration.MaxCharacters) {
            throw "Antigravity GEMINI.md 共 $length 字元，超過限制 $($targetConfiguration.MaxCharacters)。"
        }
        Write-AgentRulesLog -Level 'CHECK' -Message "Antigravity GEMINI.md：$length / $($targetConfiguration.MaxCharacters) 字元"
    }

    return $artifacts
}

function Get-ArtifactComparison {
    param(
        [Parameter(Mandatory = $true)]$Artifacts,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $results = @()
    foreach ($artifact in $Artifacts) {
        $path = Get-SafeChildPath -Root $Root -RelativePath $artifact.RelativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $status = 'Missing'
            $actualHash = $null
        }
        else {
            $actualHash = Get-FileSha256 -LiteralPath $path
            $status = if ($actualHash -eq $artifact.Hash) { 'Unchanged' } else { 'Modified' }
        }
        $results += [pscustomobject]@{
            RelativePath = $artifact.RelativePath
            FullPath = $path
            ExpectedHash = $artifact.Hash
            ActualHash = $actualHash
            Status = $status
        }
    }
    return $results
}
