[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PowerShellExecutable = (Get-Process -Id $PID -ErrorAction Stop).Path
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sandboxRoot = Join-Path $PSScriptRoot '.sandbox'
$sandboxRepository = Join-Path $sandboxRoot 'repository'
$destinationRoot = Join-Path $sandboxRoot 'destinations'
$testConfigPath = Join-Path $sandboxRepository 'config\test-targets.json'
$testSettingsPath = Join-Path $sandboxRoot 'user-settings\settings.json'
$script:Passed = 0
$script:Failed = 0

function Write-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Success,
        [string]$Detail
    )

    if ($Success) {
        $script:Passed++
        Write-Host "[PASS] $Name"
    }
    else {
        $script:Failed++
        Write-Host "[FAIL] $Name - $Detail"
    }
}

function Invoke-TestScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $scriptPath = Join-Path (Join-Path $sandboxRepository 'scripts') $ScriptName
    & $script:PowerShellExecutable `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $scriptPath `
        @Arguments |
        Out-Host
    $exitCode = $LASTEXITCODE
    return $exitCode
}

function Invoke-InteractiveMenuCheck {
    param(
        [Parameter(Mandatory = $true)][string]$EntryPoint,
        [string[]]$InputLines = @('1', '', '0')
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'cmd.exe'
    $startInfo.Arguments = '/d /c ""{0}""' -f $EntryPoint
    $startInfo.WorkingDirectory = Split-Path -Parent $EntryPoint
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        foreach ($inputLine in $InputLines) {
            $process.StandardInput.WriteLine($inputLine)
        }
        $process.StandardInput.Close()
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $standardOutput
            StandardError = $standardError
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-TreeHashes {
    param([Parameter(Mandatory = $true)][string]$Root)

    $result = @{}
    if (Test-Path -LiteralPath $Root -PathType Container) {
        Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            $result[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
    return $result
}

function Get-TreeDirectories {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
            ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') } |
            Sort-Object
    )
}

if (Test-Path -LiteralPath $sandboxRoot) {
    $resolvedSandbox = [System.IO.Path]::GetFullPath($sandboxRoot)
    $resolvedTests = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedSandbox.StartsWith($resolvedTests, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected test path: $resolvedSandbox"
    }
    Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
}

[System.IO.Directory]::CreateDirectory($sandboxRepository) | Out-Null
foreach ($directory in @('src', 'targets', 'scripts', 'config')) {
    Copy-Item `
        -LiteralPath (Join-Path $repositoryRoot $directory) `
        -Destination (Join-Path $sandboxRepository $directory) `
        -Recurse `
        -Force
}
Copy-Item `
    -LiteralPath (Join-Path $repositoryRoot 'AgentRules.cmd') `
    -Destination (Join-Path $sandboxRepository 'AgentRules.cmd') `
    -Force

$testConfig = @{
    version = 2
    targets = @{
        Codex = @{
            enabled = $true
            outputMode = 'core-with-skills'
            destination = (Join-Path $destinationRoot 'codex')
            managedFiles = @(
                'AGENTS.md',
                'skills/agent-rules-development/SKILL.md',
                'skills/agent-rules-documents/SKILL.md',
                'skills/agent-rules-terminal/SKILL.md',
                'skills/agent-rules-git/SKILL.md',
                'skills/agent-rules-security/SKILL.md',
                'skills/agent-rules-testing/SKILL.md'
            )
        }
        Antigravity = @{
            enabled = $true
            outputMode = 'core-with-skills'
            destination = (Join-Path $destinationRoot 'antigravity')
            maxCharacters = 12000
            managedFiles = @(
                'GEMINI.md',
                'config/skills/agent-rules-development/SKILL.md',
                'config/skills/agent-rules-documents/SKILL.md',
                'config/skills/agent-rules-terminal/SKILL.md',
                'config/skills/agent-rules-git/SKILL.md',
                'config/skills/agent-rules-security/SKILL.md',
                'config/skills/agent-rules-testing/SKILL.md'
            )
        }
    }
}
$json = $testConfig | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($testConfigPath, $json, $utf8NoBom)
$configArguments = @('-ConfigPath', $testConfigPath)

$originalSettingsPath = $env:AGENTRULES_SETTINGS_PATH
$originalCodexHome = $env:CODEX_HOME
$originalGeminiHome = $env:GEMINI_HOME
$env:AGENTRULES_SETTINGS_PATH = $testSettingsPath

. (Join-Path $sandboxRepository 'scripts\AgentRules.Common.ps1')

$missingSettings = Read-AgentRulesUserSettings
Write-TestResult `
    -Name 'Missing user settings are treated as first launch' `
    -Success ($null -eq $missingSettings) `
    -Detail 'Expected no initialized settings'

$detectedCodex = Join-Path $sandboxRoot 'detected\codex'
$detectedAntigravity = Join-Path $sandboxRoot 'detected\antigravity'
[System.IO.Directory]::CreateDirectory($detectedCodex) | Out-Null
[System.IO.Directory]::CreateDirectory($detectedAntigravity) | Out-Null
$env:CODEX_HOME = $detectedCodex
$env:GEMINI_HOME = $detectedAntigravity
$codexDetection = Find-AgentRulesGlobalDirectory -TargetName 'Codex' -MaximumAttempts 3
$antigravityDetection = Find-AgentRulesGlobalDirectory -TargetName 'Antigravity' -MaximumAttempts 3
Write-TestResult `
    -Name 'Global directory detection prefers configured candidates' `
    -Success (
        $codexDetection.Success -and
        $antigravityDetection.Success -and
        ($codexDetection.Path -eq $detectedCodex) -and
        ($antigravityDetection.Path -eq $detectedAntigravity)
    ) `
    -Detail "Codex: $($codexDetection.Path); Antigravity: $($antigravityDetection.Path)"

$env:CODEX_HOME = Join-Path $sandboxRoot 'missing-codex'
$limitedDetection = Find-AgentRulesGlobalDirectory -TargetName 'Codex' -MaximumAttempts 1
Write-TestResult `
    -Name 'Directory detection stops at the attempt limit' `
    -Success ((-not $limitedDetection.Success) -and ($limitedDetection.AttemptCount -eq 1)) `
    -Detail "Success: $($limitedDetection.Success); attempts: $($limitedDetection.AttemptCount)"

$savedSettings = Save-AgentRulesUserSettings `
    -CodexDestination $detectedCodex `
    -AntigravityDestination $detectedAntigravity
$loadedSettings = Read-AgentRulesUserSettings
Write-TestResult `
    -Name 'User directory settings round trip as UTF-8 JSON' `
    -Success (
        (Test-Path -LiteralPath $testSettingsPath -PathType Leaf) -and
        ($loadedSettings.Destinations.Codex -eq $detectedCodex) -and
        ($loadedSettings.Destinations.Antigravity -eq $detectedAntigravity)
    ) `
    -Detail "Settings path: $($savedSettings.SettingsPath)"

$defaultContext = Get-AgentRulesContext
$defaultCodexConfiguration = Get-TargetConfiguration `
    -Context $defaultContext `
    -TargetName 'Codex'
Write-TestResult `
    -Name 'Default configuration uses saved user destination' `
    -Success ($defaultCodexConfiguration.DestinationRoot -eq $detectedCodex) `
    -Detail "Destination: $($defaultCodexConfiguration.DestinationRoot)"

$customContext = Get-AgentRulesContext -ConfigPath $testConfigPath
$customCodexConfiguration = Get-TargetConfiguration `
    -Context $customContext `
    -TargetName 'Codex'
Write-TestResult `
    -Name 'Explicit ConfigPath remains isolated from user settings' `
    -Success ($customCodexConfiguration.DestinationRoot -eq (Join-Path $destinationRoot 'codex')) `
    -Detail "Destination: $($customCodexConfiguration.DestinationRoot)"

$entryPoint = Join-Path $sandboxRepository 'AgentRules.cmd'
& $entryPoint help | Out-Host
$exitCode = $LASTEXITCODE
Write-TestResult -Name 'CMD entry point shows help' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

& $entryPoint unknown | Out-Host
$exitCode = $LASTEXITCODE
Write-TestResult -Name 'CMD entry point rejects unknown command' -Success ($exitCode -eq 2) -Detail "Exit code $exitCode"

& $entryPoint build | Out-Host
$exitCode = $LASTEXITCODE
$entryPointBuildOutput = Join-Path $sandboxRepository 'dist\codex\AGENTS.md'
Write-TestResult `
    -Name 'CMD entry point dispatches build' `
    -Success (($exitCode -eq 0) -and (Test-Path -LiteralPath $entryPointBuildOutput -PathType Leaf)) `
    -Detail "Exit code $exitCode; output exists: $(Test-Path -LiteralPath $entryPointBuildOutput -PathType Leaf)"

Remove-Item -LiteralPath $testSettingsPath -Force
$firstLaunchResult = Invoke-InteractiveMenuCheck `
    -EntryPoint $entryPoint `
    -InputLines @('2', $detectedCodex, $detectedAntigravity, 'y', '0')
$firstLaunchSettings = Read-AgentRulesUserSettings
Write-TestResult `
    -Name 'First launch accepts manual global directories' `
    -Success (
        ($firstLaunchResult.ExitCode -eq 0) -and
        ($null -ne $firstLaunchSettings) -and
        ($firstLaunchSettings.Destinations.Codex -eq $detectedCodex) -and
        ($firstLaunchSettings.Destinations.Antigravity -eq $detectedAntigravity)
    ) `
    -Detail "Exit code $($firstLaunchResult.ExitCode); stderr: $($firstLaunchResult.StandardError)"

$interactiveResult = Invoke-InteractiveMenuCheck -EntryPoint $entryPoint
$menuSource = [System.IO.File]::ReadAllText(
    (Join-Path $sandboxRepository 'scripts\AgentRules.Menu.ps1'),
    [System.Text.Encoding]::UTF8
)
Write-TestResult `
    -Name 'Interactive menu preserves child log output and shows directory actions' `
    -Success (
        ($interactiveResult.ExitCode -eq 0) -and
        ($interactiveResult.StandardOutput -match '\[SUMMARY\]') -and
        ($menuSource -match "Write-Host '9\. 修改 Agent 目錄'") -and
        ($menuSource -match "Write-Host '10\. 重新偵測 Agent 目錄'") -and
        ($menuSource -match "Write-Host '11\. 回復備份檔案'")
    ) `
    -Detail "Exit code $($interactiveResult.ExitCode); stderr: $($interactiveResult.StandardError)"

& $entryPoint restore | Out-Host
$exitCode = $LASTEXITCODE
Write-TestResult `
    -Name 'Restore list succeeds when no backup directory exists' `
    -Success ($exitCode -eq 0) `
    -Detail "Exit code $exitCode"

$backupRoot = Join-Path $sandboxRepository 'backups'
$oldBackupNames = @(
    40..45 | ForEach-Object { (Get-Date).AddDays(-$_).ToString('yyyyMMdd-HHmmss-fff') }
)
foreach ($backupName in $oldBackupNames) {
    $backupFile = Join-Path (Join-Path $backupRoot $backupName) 'codex\AGENTS.md'
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $backupFile)) | Out-Null
    [System.IO.File]::WriteAllText($backupFile, $backupName, $utf8NoBom)
}
$legacyBackup = Join-Path $backupRoot 'legacy-rules-20260720'
[System.IO.Directory]::CreateDirectory($legacyBackup) | Out-Null

& $entryPoint cleanup | Out-Host
$exitCode = $LASTEXITCODE
$backupCountAfterPreview = @(
    Get-ChildItem -LiteralPath $backupRoot -Directory |
        Where-Object { $_.Name -match '^\d{8}-\d{6}-\d{3}$' }
).Count
Write-TestResult `
    -Name 'Backup cleanup preview does not delete files' `
    -Success (($exitCode -eq 0) -and ($backupCountAfterPreview -eq 6)) `
    -Detail "Exit code $exitCode; timestamp backups: $backupCountAfterPreview"

& $entryPoint cleanup --apply | Out-Host
$exitCode = $LASTEXITCODE
$backupCountAfterCleanup = @(
    Get-ChildItem -LiteralPath $backupRoot -Directory |
        Where-Object { $_.Name -match '^\d{8}-\d{6}-\d{3}$' }
).Count
Write-TestResult `
    -Name 'Backup cleanup keeps latest five and preserves legacy directory' `
    -Success (
        ($exitCode -eq 0) -and
        ($backupCountAfterCleanup -eq 5) -and
        (Test-Path -LiteralPath $legacyBackup -PathType Container)
    ) `
    -Detail "Exit code $exitCode; timestamp backups: $backupCountAfterCleanup"

$exitCode = Invoke-TestScript -ScriptName 'Build-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Write-TestResult -Name 'Build all targets' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

$codexSkillPath = Join-Path $sandboxRepository 'dist\codex\skills\agent-rules-development\SKILL.md'
$antigravitySkillPath = Join-Path $sandboxRepository 'dist\antigravity\config\skills\agent-rules-development\SKILL.md'
$codexSkillContent = if (Test-Path -LiteralPath $codexSkillPath) {
    [System.IO.File]::ReadAllText($codexSkillPath, [System.Text.Encoding]::UTF8)
}
else {
    ''
}
Write-TestResult `
    -Name 'Build emits portable skills for both targets' `
    -Success (
        (Test-Path -LiteralPath $codexSkillPath -PathType Leaf) -and
        (Test-Path -LiteralPath $antigravitySkillPath -PathType Leaf) -and
        ($codexSkillContent -match '\A---\nname: agent-rules-development\n') -and
        ((Get-FileHash -LiteralPath $codexSkillPath -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $antigravitySkillPath -Algorithm SHA256).Hash)
    ) `
    -Detail 'Skill output is missing, malformed, or differs between targets'

$exitCode = Invoke-TestScript -ScriptName 'Check-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Write-TestResult -Name 'Check reports unsynced destinations' -Success ($exitCode -eq 1) -Detail "Exit code $exitCode"

$exitCode = Invoke-TestScript -ScriptName 'Sync-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
$previewCreatedDestination = Test-Path -LiteralPath $destinationRoot
Write-TestResult `
    -Name 'Preview does not write destinations' `
    -Success (($exitCode -eq 0) -and (-not $previewCreatedDestination)) `
    -Detail "Exit code $exitCode; destination exists: $previewCreatedDestination"

$exitCode = Invoke-TestScript `
    -ScriptName 'Sync-AgentRules.ps1' `
    -Arguments (@('-Target', 'All', '-Apply') + $configArguments)
Write-TestResult -Name 'Initial sync' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

$restoreBackupId = '20990101-010203-004'
$restoreBackupFile = Join-Path `
    (Join-Path (Join-Path $sandboxRepository 'backups') $restoreBackupId) `
    'codex\AGENTS.md'
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $restoreBackupFile)) | Out-Null
$restoreBytes = @(
    [byte]0xEF,
    [byte]0xBB,
    [byte]0xBF
) + [System.Text.Encoding]::UTF8.GetBytes("historical restore`r`nbyte preserving")
[System.IO.File]::WriteAllBytes($restoreBackupFile, $restoreBytes)

$restoreMenuResult = Invoke-InteractiveMenuCheck `
    -EntryPoint $entryPoint `
    -InputLines @('11', '1', 'Codex', 'n', '', '0')
Write-TestResult `
    -Name 'Interactive restore menu selects a backup by number' `
    -Success (
        ($restoreMenuResult.ExitCode -eq 0) -and
        ($restoreMenuResult.StandardOutput -match "1\. $restoreBackupId") -and
        ([regex]::Matches(
            $restoreMenuResult.StandardOutput,
            [regex]::Escape($restoreBackupId)
        ).Count -ge 2)
    ) `
    -Detail "Exit code $($restoreMenuResult.ExitCode); stderr: $($restoreMenuResult.StandardError)"

$codexAgents = Join-Path (Join-Path $destinationRoot 'codex') 'AGENTS.md'
$destinationHashBeforeRestore = (Get-FileHash -LiteralPath $codexAgents -Algorithm SHA256).Hash
$destinationTreeBeforeRestorePreview = Get-TreeHashes -Root $destinationRoot
$backupTreeBeforeRestorePreview = Get-TreeHashes -Root (Join-Path $sandboxRepository 'backups')
$destinationDirectoriesBeforeRestorePreview = Get-TreeDirectories -Root $destinationRoot
$backupDirectoriesBeforeRestorePreview = Get-TreeDirectories -Root (Join-Path $sandboxRepository 'backups')
$exitCode = Invoke-TestScript `
    -ScriptName 'Restore-AgentRulesBackup.ps1' `
    -Arguments (@($restoreBackupId, '-Target', 'Codex') + $configArguments)
$destinationTreeAfterRestorePreview = Get-TreeHashes -Root $destinationRoot
$backupTreeAfterRestorePreview = Get-TreeHashes -Root (Join-Path $sandboxRepository 'backups')
$destinationDirectoriesAfterRestorePreview = Get-TreeDirectories -Root $destinationRoot
$backupDirectoriesAfterRestorePreview = Get-TreeDirectories -Root (Join-Path $sandboxRepository 'backups')
$destinationPreviewDiff = @(
    Compare-Object $destinationTreeBeforeRestorePreview.GetEnumerator() $destinationTreeAfterRestorePreview.GetEnumerator()
)
$backupPreviewDiff = @(
    Compare-Object $backupTreeBeforeRestorePreview.GetEnumerator() $backupTreeAfterRestorePreview.GetEnumerator()
)
$destinationDirectoryPreviewDiff = @(
    Compare-Object $destinationDirectoriesBeforeRestorePreview $destinationDirectoriesAfterRestorePreview
)
$backupDirectoryPreviewDiff = @(
    Compare-Object $backupDirectoriesBeforeRestorePreview $backupDirectoriesAfterRestorePreview
)
Write-TestResult `
    -Name 'Restore preview performs no destination or backup writes' `
    -Success (
        ($exitCode -eq 0) -and
        ($destinationPreviewDiff.Count -eq 0) -and
        ($backupPreviewDiff.Count -eq 0) -and
        ($destinationDirectoryPreviewDiff.Count -eq 0) -and
        ($backupDirectoryPreviewDiff.Count -eq 0)
    ) `
    -Detail (
        "Exit code $exitCode; destination file diff $($destinationPreviewDiff.Count); " +
        "backup file diff $($backupPreviewDiff.Count); destination directory diff " +
        "$($destinationDirectoryPreviewDiff.Count); backup directory diff $($backupDirectoryPreviewDiff.Count)"
    )

& $entryPoint restore | Out-Host
$exitCode = $LASTEXITCODE
Write-TestResult `
    -Name 'Restore command without BackupId lists backups' `
    -Success ($exitCode -eq 0) `
    -Detail "Exit code $exitCode"

& $entryPoint restore --apply | Out-Host
$exitCode = $LASTEXITCODE
Write-TestResult `
    -Name 'Restore apply requires BackupId' `
    -Success ($exitCode -eq 2) `
    -Detail "Exit code $exitCode"

$backupIdsBeforeRestoreApply = @(
    Get-ChildItem -LiteralPath (Join-Path $sandboxRepository 'backups') -Directory -Force |
        Select-Object -ExpandProperty Name
)
$exitCode = Invoke-TestScript `
    -ScriptName 'Restore-AgentRulesBackup.ps1' `
    -Arguments (@($restoreBackupId, '-Target', 'Codex', '-Apply') + $configArguments)
$restoredHash = (Get-FileHash -LiteralPath $codexAgents -Algorithm SHA256).Hash
$backupIdsAfterRestoreApply = @(
    Get-ChildItem -LiteralPath (Join-Path $sandboxRepository 'backups') -Directory -Force |
        Select-Object -ExpandProperty Name
)
$newProtectionBackupIds = @(
    Compare-Object $backupIdsBeforeRestoreApply $backupIdsAfterRestoreApply |
        Where-Object { $_.SideIndicator -eq '=>' } |
        Select-Object -ExpandProperty InputObject
)
$protectionCopies = @(
    foreach ($newProtectionBackupId in $newProtectionBackupIds) {
        $newProtectionRoot = Join-Path (Join-Path $sandboxRepository 'backups') $newProtectionBackupId
        Get-ChildItem -LiteralPath $newProtectionRoot -Recurse -File -Filter 'AGENTS.md' |
            Where-Object {
                (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq
                    $destinationHashBeforeRestore
            }
        }
    )
Write-TestResult `
    -Name 'Restore apply preserves bytes and creates a protection backup' `
    -Success (
        ($exitCode -eq 0) -and
        ($restoredHash -eq (Get-FileHash -LiteralPath $restoreBackupFile -Algorithm SHA256).Hash) -and
        ($newProtectionBackupIds.Count -eq 1) -and
        ($protectionCopies.Count -gt 0)
    ) `
    -Detail (
        "Exit code $exitCode; new protection backups $($newProtectionBackupIds.Count); " +
        "matching protection copies $($protectionCopies.Count)"
    )

$exitCode = Invoke-TestScript `
    -ScriptName 'Sync-AgentRules.ps1' `
    -Arguments (@('-Target', 'Codex', '-Apply') + $configArguments)
Write-TestResult `
    -Name 'Sync can replace restored historical content' `
    -Success ($exitCode -eq 0) `
    -Detail "Exit code $exitCode"

$unmanagedBackupId = '20990101-010203-005'
$unmanagedBackupRoot = Join-Path `
    (Join-Path (Join-Path $sandboxRepository 'backups') $unmanagedBackupId) `
    'codex'
[System.IO.Directory]::CreateDirectory($unmanagedBackupRoot) | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $unmanagedBackupRoot 'auth.json'),
    '{"unmanaged":true}',
    $utf8NoBom
)
$hashBeforeRejectedRestore = (Get-FileHash -LiteralPath $codexAgents -Algorithm SHA256).Hash
$exitCode = Invoke-TestScript `
    -ScriptName 'Restore-AgentRulesBackup.ps1' `
    -Arguments (@($unmanagedBackupId, '-Target', 'Codex', '-Apply') + $configArguments)
$hashAfterRejectedRestore = (Get-FileHash -LiteralPath $codexAgents -Algorithm SHA256).Hash
Write-TestResult `
    -Name 'Restore rejects an entire backup containing unmanaged files' `
    -Success (
        ($exitCode -eq 2) -and
        ($hashBeforeRejectedRestore -eq $hashAfterRejectedRestore)
    ) `
    -Detail "Exit code $exitCode"

$missingDestinationBackupId = '20990101-010203-006'
$missingDestinationRelativePath = 'skills/agent-rules-testing/SKILL.md'
$missingDestinationBackupFile = Join-Path `
    (Join-Path (Join-Path $sandboxRepository 'backups') $missingDestinationBackupId) `
    ('codex\' + ($missingDestinationRelativePath -replace '/', '\'))
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $missingDestinationBackupFile)) | Out-Null
[System.IO.File]::WriteAllText($missingDestinationBackupFile, 'restored missing file', $utf8NoBom)
$missingDestinationPath = Join-Path `
    (Join-Path $destinationRoot 'codex') `
    ($missingDestinationRelativePath -replace '/', '\')
Remove-Item -LiteralPath $missingDestinationPath -Force
$exitCode = Invoke-TestScript `
    -ScriptName 'Restore-AgentRulesBackup.ps1' `
    -Arguments (@($missingDestinationBackupId, '-Target', 'Codex', '-Apply') + $configArguments)
Write-TestResult `
    -Name 'Restore can recreate a missing managed destination file' `
    -Success (
        ($exitCode -eq 0) -and
        ((Get-FileHash -LiteralPath $missingDestinationPath -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $missingDestinationBackupFile -Algorithm SHA256).Hash)
    ) `
    -Detail "Exit code $exitCode"

$exitCode = Invoke-TestScript `
    -ScriptName 'Sync-AgentRules.ps1' `
    -Arguments (@('-Target', 'Codex', '-Apply') + $configArguments)
Write-TestResult `
    -Name 'Sync repairs a recreated historical managed file' `
    -Success ($exitCode -eq 0) `
    -Detail "Exit code $exitCode"

$atomicBackupId = '20990101-010203-007'
$atomicCodexBackup = Join-Path `
    (Join-Path (Join-Path $sandboxRepository 'backups') $atomicBackupId) `
    'codex\AGENTS.md'
$atomicAntigravityBackup = Join-Path `
    (Join-Path (Join-Path $sandboxRepository 'backups') $atomicBackupId) `
    'antigravity\unknown.txt'
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $atomicCodexBackup)) | Out-Null
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $atomicAntigravityBackup)) | Out-Null
[System.IO.File]::WriteAllText($atomicCodexBackup, 'must not apply', $utf8NoBom)
[System.IO.File]::WriteAllText($atomicAntigravityBackup, 'reject all', $utf8NoBom)
$hashBeforeAtomicRejection = (Get-FileHash -LiteralPath $codexAgents -Algorithm SHA256).Hash
$exitCode = Invoke-TestScript `
    -ScriptName 'Restore-AgentRulesBackup.ps1' `
    -Arguments (@($atomicBackupId, '-Target', 'All', '-Apply') + $configArguments)
$hashAfterAtomicRejection = (Get-FileHash -LiteralPath $codexAgents -Algorithm SHA256).Hash
Write-TestResult `
    -Name 'Restore completes all-target preflight before changing destinations' `
    -Success (
        ($exitCode -eq 2) -and
        ($hashBeforeAtomicRejection -eq $hashAfterAtomicRejection)
    ) `
    -Detail "Exit code $exitCode"

$exitCode = Invoke-TestScript -ScriptName 'Check-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Write-TestResult -Name 'Check after initial sync' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

$hashesBeforeRepeat = Get-TreeHashes -Root $destinationRoot
$backupsBeforeRepeat = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRepository 'backups') -Recurse -File -ErrorAction SilentlyContinue).Count
$exitCode = Invoke-TestScript `
    -ScriptName 'Sync-AgentRules.ps1' `
    -Arguments (@('-Target', 'All', '-Apply') + $configArguments)
$hashesAfterRepeat = Get-TreeHashes -Root $destinationRoot
$backupsAfterRepeat = @(Get-ChildItem -LiteralPath (Join-Path $sandboxRepository 'backups') -Recurse -File -ErrorAction SilentlyContinue).Count
$repeatHashDiff = @(Compare-Object $hashesBeforeRepeat.GetEnumerator() $hashesAfterRepeat.GetEnumerator())
Write-TestResult `
    -Name 'Repeated sync is idempotent' `
    -Success (($exitCode -eq 0) -and ($repeatHashDiff.Count -eq 0) -and ($backupsBeforeRepeat -eq $backupsAfterRepeat)) `
    -Detail "Exit code $exitCode; backup files $backupsBeforeRepeat -> $backupsAfterRepeat"

$unknownFile = Join-Path (Join-Path $destinationRoot 'codex') 'auth.json'
[System.IO.File]::WriteAllText($unknownFile, '{"preserve":true}', $utf8NoBom)
$unknownHash = (Get-FileHash -LiteralPath $unknownFile -Algorithm SHA256).Hash
$unknownSkill = Join-Path (Join-Path $destinationRoot 'codex') 'skills\user-owned\SKILL.md'
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $unknownSkill)) | Out-Null
[System.IO.File]::WriteAllText($unknownSkill, 'user-owned', $utf8NoBom)
$unknownSkillHash = (Get-FileHash -LiteralPath $unknownSkill -Algorithm SHA256).Hash

[System.IO.File]::AppendAllText($codexAgents, "`nmanual edit", $utf8NoBom)
$exitCode = Invoke-TestScript -ScriptName 'Check-AgentRules.ps1' -Arguments (@('-Target', 'Codex') + $configArguments)
Write-TestResult -Name 'Check detects manual destination edit' -Success ($exitCode -eq 1) -Detail "Exit code $exitCode"

$antigravityPath = Join-Path (Join-Path $destinationRoot 'antigravity') 'GEMINI.md'
$antigravityHashBefore = (Get-FileHash -LiteralPath $antigravityPath -Algorithm SHA256).Hash
$exitCode = Invoke-TestScript `
    -ScriptName 'Sync-AgentRules.ps1' `
    -Arguments (@('-Target', 'Codex', '-Apply') + $configArguments)
$antigravityHashAfter = (Get-FileHash -LiteralPath $antigravityPath -Algorithm SHA256).Hash
$unknownHashAfter = (Get-FileHash -LiteralPath $unknownFile -Algorithm SHA256).Hash
$unknownSkillHashAfter = (Get-FileHash -LiteralPath $unknownSkill -Algorithm SHA256).Hash
$backupFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $sandboxRepository 'backups') -Recurse -File -ErrorAction SilentlyContinue
)
Write-TestResult `
    -Name 'Single-target sync leaves other target unchanged' `
    -Success (($exitCode -eq 0) -and ($antigravityHashBefore -eq $antigravityHashAfter)) `
    -Detail "Exit code $exitCode"
Write-TestResult `
    -Name 'Backup is created for overwritten file' `
    -Success (@($backupFiles | Where-Object { $_.Name -eq 'AGENTS.md' }).Count -gt 0) `
    -Detail "Backup files: $($backupFiles.Count)"
Write-TestResult `
    -Name 'Unknown destination file is preserved' `
    -Success (
        (Test-Path -LiteralPath $unknownFile -PathType Leaf) -and
        ($unknownHash -eq $unknownHashAfter) -and
        (Test-Path -LiteralPath $unknownSkill -PathType Leaf) -and
        ($unknownSkillHash -eq $unknownSkillHashAfter)
    ) `
    -Detail 'Unknown file changed or was removed'

$missingSource = Join-Path $sandboxRepository 'src\skills\agent-rules-testing\SKILL.md'
$heldSource = $missingSource + '.held'
Move-Item -LiteralPath $missingSource -Destination $heldSource
$exitCode = Invoke-TestScript -ScriptName 'Build-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Move-Item -LiteralPath $heldSource -Destination $missingSource
Write-TestResult -Name 'Missing source stops build' -Success ($exitCode -eq 2) -Detail "Exit code $exitCode"

$invalidSkill = Join-Path $sandboxRepository 'src\skills\agent-rules-testing\SKILL.md'
$validSkillContent = [System.IO.File]::ReadAllText($invalidSkill, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText(
    $invalidSkill,
    ($validSkillContent -replace 'name: agent-rules-testing', 'name: wrong-name'),
    $utf8NoBom
)
$exitCode = Invoke-TestScript -ScriptName 'Build-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
[System.IO.File]::WriteAllText($invalidSkill, $validSkillContent, $utf8NoBom)
Write-TestResult -Name 'Invalid skill metadata stops build' -Success ($exitCode -eq 2) -Detail "Exit code $exitCode"

$exitCode = Invoke-TestScript -ScriptName 'Check-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Write-TestResult -Name 'Final no-difference check' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

Write-Host
$env:AGENTRULES_SETTINGS_PATH = $originalSettingsPath
$env:CODEX_HOME = $originalCodexHome
$env:GEMINI_HOME = $originalGeminiHome

if ($script:Failed -gt 0) {
    Write-Host `
        "[SUMMARY] 測試結果：Passed: $script:Passed; Failed: $script:Failed" `
        -ForegroundColor White `
        -BackgroundColor Red
    Write-Host
    exit 1
}

Write-Host `
    "[SUMMARY] 測試結果：Passed: $script:Passed; Failed: $script:Failed" `
    -ForegroundColor Black `
    -BackgroundColor Yellow
Write-Host
exit 0
