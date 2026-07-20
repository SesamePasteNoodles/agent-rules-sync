[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sandboxRoot = Join-Path $PSScriptRoot '.sandbox'
$sandboxRepository = Join-Path $sandboxRoot 'repository'
$destinationRoot = Join-Path $sandboxRoot 'destinations'
$testConfigPath = Join-Path $sandboxRepository 'config\test-targets.json'
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
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments | Out-Host
    $exitCode = $LASTEXITCODE
    return $exitCode
}

function Invoke-InteractiveMenuCheck {
    param([Parameter(Mandatory = $true)][string]$EntryPoint)

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
        $process.StandardInput.WriteLine('1')
        $process.StandardInput.WriteLine('')
        $process.StandardInput.WriteLine('0')
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
    version = 1
    targets = @{
        Codex = @{
            enabled = $true
            outputMode = 'modular'
            destination = (Join-Path $destinationRoot 'codex')
            managedFiles = @(
                'AGENTS.md',
                'rules/development.md',
                'rules/documents.md',
                'rules/git.md',
                'rules/security.md',
                'rules/terminal.md',
                'rules/testing.md'
            )
        }
        Antigravity = @{
            enabled = $true
            outputMode = 'single-file'
            destination = (Join-Path $destinationRoot 'antigravity')
            maxCharacters = 12000
            managedFiles = @('GEMINI.md')
        }
    }
}
$json = $testConfig | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($testConfigPath, $json, $utf8NoBom)
$configArguments = @('-ConfigPath', $testConfigPath)

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

$interactiveResult = Invoke-InteractiveMenuCheck -EntryPoint $entryPoint
Write-TestResult `
    -Name 'Interactive menu preserves child log output' `
    -Success (($interactiveResult.ExitCode -eq 0) -and ($interactiveResult.StandardOutput -match '\[SUMMARY\]')) `
    -Detail "Exit code $($interactiveResult.ExitCode); stderr: $($interactiveResult.StandardError)"

$exitCode = Invoke-TestScript -ScriptName 'Build-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Write-TestResult -Name 'Build all targets' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

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

$codexAgents = Join-Path (Join-Path $destinationRoot 'codex') 'AGENTS.md'
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
    -Success ((Test-Path -LiteralPath $unknownFile -PathType Leaf) -and ($unknownHash -eq $unknownHashAfter)) `
    -Detail 'Unknown file changed or was removed'

$missingSource = Join-Path $sandboxRepository 'src\rules\testing.md'
$heldSource = $missingSource + '.held'
Move-Item -LiteralPath $missingSource -Destination $heldSource
$exitCode = Invoke-TestScript -ScriptName 'Build-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Move-Item -LiteralPath $heldSource -Destination $missingSource
Write-TestResult -Name 'Missing source stops build' -Success ($exitCode -eq 2) -Detail "Exit code $exitCode"

$exitCode = Invoke-TestScript -ScriptName 'Check-AgentRules.ps1' -Arguments (@('-Target', 'All') + $configArguments)
Write-TestResult -Name 'Final no-difference check' -Success ($exitCode -eq 0) -Detail "Exit code $exitCode"

Write-Host
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
