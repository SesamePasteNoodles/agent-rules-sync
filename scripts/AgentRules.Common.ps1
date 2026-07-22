Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GeneratedWarning = @'
<!--
此檔案由同步系統自動產生。
請勿直接修改，來源位於 AI Agent 規範專案。
-->
'@

$script:SkillNames = @(
    'agent-rules-development'
    'agent-rules-documents'
    'agent-rules-terminal'
    'agent-rules-git'
    'agent-rules-security'
    'agent-rules-testing'
)

function Write-AgentRulesLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'CHECK', 'CHANGE', 'BACKUP', 'OK', 'WARN', 'ERROR', 'SUMMARY')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Level -eq 'SUMMARY') {
        Write-Host
        Write-Host ('[{0}] {1}' -f $Level, $Message) -ForegroundColor Black -BackgroundColor Yellow
        Write-Host
        return
    }

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

function Get-AgentRulesSettingsPath {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTRULES_SETTINGS_PATH)) {
        return [System.IO.Path]::GetFullPath(
            [System.Environment]::ExpandEnvironmentVariables($env:AGENTRULES_SETTINGS_PATH)
        )
    }

    $localAppData = [System.Environment]::GetFolderPath(
        [System.Environment+SpecialFolder]::LocalApplicationData
    )
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw '無法取得 LOCALAPPDATA，不能決定使用者設定檔位置。'
    }

    return Join-Path (Join-Path $localAppData 'AgentRules') 'settings.json'
}

function ConvertTo-AgentRulesDestinationPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ([string]::IsNullOrWhiteSpace($expandedPath)) {
        throw 'Agent 全域目錄不可為空。'
    }

    $fullPath = [System.IO.Path]::GetFullPath($expandedPath)
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        throw "Agent 全域目錄不可指向檔案：$fullPath"
    }
    return $fullPath
}

function Read-AgentRulesUserSettings {
    param([string]$SettingsPath = (Get-AgentRulesSettingsPath))

    $resolvedPath = [System.IO.Path]::GetFullPath($SettingsPath)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return $null
    }

    try {
        $settings = (Read-Utf8Text -LiteralPath $resolvedPath) | ConvertFrom-Json
    }
    catch {
        throw "使用者設定檔無法解析：$resolvedPath。$($_.Exception.Message)"
    }

    if (($settings.version -ne 1) -or ($settings.initialized -ne $true)) {
        throw "使用者設定檔格式無效：$resolvedPath"
    }
    if ($null -eq $settings.destinations) {
        throw "使用者設定檔缺少 destinations：$resolvedPath"
    }

    $destinations = [ordered]@{}
    foreach ($targetName in @('Codex', 'Antigravity')) {
        $property = $settings.destinations.PSObject.Properties[$targetName]
        if (($null -eq $property) -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "使用者設定檔缺少 $targetName 全域目錄：$resolvedPath"
        }
        $destinations[$targetName] = ConvertTo-AgentRulesDestinationPath -Path ([string]$property.Value)
    }

    return [pscustomobject]@{
        Version = 1
        Initialized = $true
        SettingsPath = $resolvedPath
        Destinations = [pscustomobject]$destinations
    }
}

function Save-AgentRulesUserSettings {
    param(
        [Parameter(Mandatory = $true)][string]$CodexDestination,
        [Parameter(Mandatory = $true)][string]$AntigravityDestination,
        [string]$SettingsPath = (Get-AgentRulesSettingsPath)
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($SettingsPath)
    $codexPath = ConvertTo-AgentRulesDestinationPath -Path $CodexDestination
    $antigravityPath = ConvertTo-AgentRulesDestinationPath -Path $AntigravityDestination
    $settings = [ordered]@{
        version = 1
        initialized = $true
        destinations = [ordered]@{
            Codex = $codexPath
            Antigravity = $antigravityPath
        }
    }
    $content = ($settings | ConvertTo-Json -Depth 4) + "`n"
    $temporaryPath = $resolvedPath + '.tmp-' + [System.Guid]::NewGuid().ToString('N')

    try {
        Write-Utf8NoBomText -LiteralPath $temporaryPath -Content $content
        Move-Item -LiteralPath $temporaryPath -Destination $resolvedPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    return Read-AgentRulesUserSettings -SettingsPath $resolvedPath
}

function Get-AgentRulesDetectionCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Codex', 'Antigravity')]
        [string]$TargetName
    )

    $candidateValues = if ($TargetName -eq 'Codex') {
        @($env:CODEX_HOME, (Join-Path $HOME '.codex'))
    }
    else {
        @($env:GEMINI_HOME, (Join-Path $HOME '.gemini'))
    }

    $candidates = @()
    foreach ($candidateValue in $candidateValues) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateValue)) {
            continue
        }
        try {
            $candidate = ConvertTo-AgentRulesDestinationPath -Path ([string]$candidateValue)
        }
        catch {
            continue
        }
        if (-not ($candidates -contains $candidate)) {
            $candidates += $candidate
        }
        if ($candidates.Count -ge 3) {
            break
        }
    }
    return $candidates
}

function Find-AgentRulesGlobalDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Codex', 'Antigravity')]
        [string]$TargetName,

        [ValidateRange(1, 10)]
        [int]$MaximumAttempts = 3
    )

    $attemptCount = 0
    $detectedPath = $null
    $candidates = @(Get-AgentRulesDetectionCandidates -TargetName $TargetName)
    foreach ($candidate in $candidates) {
        if ($attemptCount -ge $MaximumAttempts) {
            break
        }
        $attemptCount++
        try {
            if (Test-Path -LiteralPath $candidate -PathType Container -ErrorAction Stop) {
                $detectedPath = $candidate
                break
            }
        }
        catch {
            continue
        }
    }

    return [pscustomobject]@{
        TargetName = $TargetName
        Path = $detectedPath
        Success = -not [string]::IsNullOrWhiteSpace($detectedPath)
        AttemptCount = $attemptCount
        MaximumAttempts = $MaximumAttempts
    }
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

    $stream = [System.IO.File]::OpenRead($LiteralPath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
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
    if ($config.version -ne 2) {
        throw '設定檔 version 必須是 2。'
    }

    $userSettings = $null
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $userSettings = Read-AgentRulesUserSettings
    }

    return [pscustomobject]@{
        RepositoryRoot = $repositoryRoot
        ConfigPath = $resolvedConfigPath
        Config = $config
        UserSettings = $userSettings
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

    $entryFile = if ($TargetName -eq 'Codex') { 'AGENTS.md' } else { 'GEMINI.md' }
    $skillPrefix = if ($TargetName -eq 'Codex') { 'skills' } else { 'config/skills' }
    $files = @($entryFile)
    if ($TargetName -eq 'Antigravity') {
        $files += 'antigravity/settings.json'
    }
    foreach ($skillName in $script:SkillNames) {
        $files += "$skillPrefix/$skillName/SKILL.md"
    }
    return $files
}

function Get-TargetConfiguration {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('Codex', 'Antigravity')][string]$TargetName
    )

    $targetConfig = $Context.Config.targets.PSObject.Properties[$TargetName].Value
    $expectedMode = 'core-with-skills'
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

    $configuredDestination = [string]$targetConfig.destination
    if ($null -ne $Context.UserSettings) {
        $settingsProperty = $Context.UserSettings.Destinations.PSObject.Properties[$TargetName]
        if ($null -ne $settingsProperty) {
            $configuredDestination = [string]$settingsProperty.Value
        }
    }

    $expandedDestination = [System.Environment]::ExpandEnvironmentVariables($configuredDestination)
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

function Get-ValidatedSkillSource {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    if ($SkillName -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Skill 名稱格式無效：$SkillName"
    }

    $sourcePath = Join-Path (Join-Path (Join-Path $Context.RepositoryRoot 'src') 'skills') "$SkillName\SKILL.md"
    $content = ConvertTo-NormalizedMarkdown -Content (Read-Utf8Text -LiteralPath $sourcePath)
    $frontmatterMatch = [System.Text.RegularExpressions.Regex]::Match(
        $content,
        '\A---\n(?<frontmatter>.*?)\n---\n(?<body>[\s\S]*)\z',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $frontmatterMatch.Success) {
        throw "Skill 缺少有效的 YAML frontmatter：$sourcePath"
    }

    $frontmatter = $frontmatterMatch.Groups['frontmatter'].Value
    $nameMatch = [System.Text.RegularExpressions.Regex]::Match(
        $frontmatter,
        '(?m)^name:\s*(?<value>[^\r\n#]+?)\s*$'
    )
    $descriptionMatch = [System.Text.RegularExpressions.Regex]::Match(
        $frontmatter,
        '(?m)^description:\s*(?<value>[^\r\n#]+?)\s*$'
    )
    if (-not $nameMatch.Success -or $nameMatch.Groups['value'].Value -ne $SkillName) {
        throw "Skill frontmatter 的 name 必須等於目錄名稱：$SkillName"
    }
    if (-not $descriptionMatch.Success -or [string]::IsNullOrWhiteSpace($descriptionMatch.Groups['value'].Value)) {
        throw "Skill frontmatter 缺少 description：$SkillName"
    }
    $description = $descriptionMatch.Groups['value'].Value.Trim()
    if ($SkillName.Length -gt 64) {
        throw "Skill 名稱不可超過 64 個字元：$SkillName"
    }
    if ($description.Length -gt 1024 -or $description.Contains('<') -or $description.Contains('>')) {
        throw "Skill description 格式無效：$SkillName"
    }
    if ([string]::IsNullOrWhiteSpace($frontmatterMatch.Groups['body'].Value)) {
        throw "Skill 內容不可為空：$SkillName"
    }

    return [pscustomobject]@{
        Name = $SkillName
        Frontmatter = $frontmatter
        Description = $description
        Body = $frontmatterMatch.Groups['body'].Value.Trim()
    }
}

function ConvertTo-GeneratedSkillContent {
    param([Parameter(Mandatory = $true)]$SkillSource)

    $warning = (ConvertTo-NormalizedMarkdown -Content $script:GeneratedWarning).Trim()
    return (
        "---`n" +
        $SkillSource.Frontmatter.Trim() +
        "`n---`n`n" +
        $warning +
        "`n`n" +
        $SkillSource.Body.Trim() +
        "`n"
    )
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

    $entryContent = $warning + "`n" + $header + "`n" + $core
    $entryRelativePath = if ($TargetName -eq 'Codex') { 'AGENTS.md' } else { 'GEMINI.md' }
    $artifacts += [pscustomobject]@{
        RelativePath = $entryRelativePath
        Content = $entryContent
        Hash = Get-TextSha256 -Content $entryContent
    }

    if ($TargetName -eq 'Antigravity') {
        $settingsPath = Join-Path $targetsRoot 'antigravity-settings.json'
        $settingsContent = (Read-Utf8Text -LiteralPath $settingsPath).Trim() + "`n"
        try {
            $null = $settingsContent | ConvertFrom-Json
        }
        catch {
            throw "Antigravity settings JSON 無法解析：$settingsPath。$($_.Exception.Message)"
        }
        $artifacts += [pscustomobject]@{
            RelativePath = 'antigravity/settings.json'
            Content = $settingsContent
            Hash = Get-TextSha256 -Content $settingsContent
        }
    }

    $skillPrefix = if ($TargetName -eq 'Codex') { 'skills' } else { 'config/skills' }
    foreach ($skillName in $script:SkillNames) {
        $skillSource = Get-ValidatedSkillSource -Context $Context -SkillName $skillName
        $skillContent = ConvertTo-GeneratedSkillContent -SkillSource $skillSource
        $relativePath = "$skillPrefix/$skillName/SKILL.md"
        $artifacts += [pscustomobject]@{
            RelativePath = $relativePath
            Content = $skillContent
            Hash = Get-TextSha256 -Content $skillContent
        }
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
