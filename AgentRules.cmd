@echo off
setlocal
set "ROOT=%~dp0"
pushd "%ROOT%" >nul

if "%~1"=="" goto menu
if /I "%~1"=="check" goto command_check
if /I "%~1"=="preview" goto command_preview
if /I "%~1"=="sync" goto command_sync
if /I "%~1"=="codex" goto command_codex
if /I "%~1"=="antigravity" goto command_antigravity
if /I "%~1"=="build" goto command_build
if /I "%~1"=="test" goto command_test
if /I "%~1"=="help" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="-h" goto usage

echo [ERROR] Unknown command: %~1
echo.
goto usage_error

:menu
cls
echo ========================================
echo AI Agent Rules Manager
echo ========================================
echo.
echo 1. Check status
echo 2. Preview sync
echo 3. Sync all
echo 4. Sync Codex only
echo 5. Sync Antigravity only
echo 6. Run tests
echo 0. Exit
echo.
set "SELECTION="
set /p "SELECTION=Select an option: "

if "%SELECTION%"=="1" goto menu_check
if "%SELECTION%"=="2" goto menu_preview
if "%SELECTION%"=="3" goto menu_sync
if "%SELECTION%"=="4" goto menu_codex
if "%SELECTION%"=="5" goto menu_antigravity
if "%SELECTION%"=="6" goto menu_test
if "%SELECTION%"=="0" goto exit_success

echo.
echo [ERROR] Invalid option.
pause
goto menu

:menu_check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Check-AgentRules.ps1" -Target "All"
set "RESULT=%ERRORLEVEL%"
goto show_menu_result

:menu_preview
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "All"
set "RESULT=%ERRORLEVEL%"
goto show_menu_result

:menu_sync
call :confirm_apply "Codex and Antigravity"
if errorlevel 1 goto menu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "All" -Apply
set "RESULT=%ERRORLEVEL%"
goto show_menu_result

:menu_codex
call :confirm_apply "Codex"
if errorlevel 1 goto menu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "Codex" -Apply
set "RESULT=%ERRORLEVEL%"
goto show_menu_result

:menu_antigravity
call :confirm_apply "Antigravity"
if errorlevel 1 goto menu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "Antigravity" -Apply
set "RESULT=%ERRORLEVEL%"
goto show_menu_result

:menu_test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tests\Test-AgentRules.ps1"
set "RESULT=%ERRORLEVEL%"
goto show_menu_result

:show_menu_result
echo.
echo Finished with exit code %RESULT%.
set "CONTINUE="
set /p "CONTINUE=Press Enter to return to the menu..."
goto menu

:command_check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Check-AgentRules.ps1" -Target "All"
goto exit_with_result

:command_preview
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "All"
goto exit_with_result

:command_sync
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "All" -Apply
goto exit_with_result

:command_codex
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "Codex" -Apply
goto exit_with_result

:command_antigravity
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Sync-AgentRules.ps1" -Target "Antigravity" -Apply
goto exit_with_result

:command_build
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Build-AgentRules.ps1" -Target "All"
goto exit_with_result

:command_test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tests\Test-AgentRules.ps1"
goto exit_with_result

:confirm_apply
echo.
echo This will update the global rules for %~1.
set "CONFIRM="
set /p "CONFIRM=Continue? [y/N]: "
if /I "%CONFIRM%"=="Y" exit /b 0
echo Cancelled.
exit /b 1

:usage
echo AI Agent Rules Manager
echo.
echo Double-click AgentRules.cmd to open the interactive menu.
echo.
echo Command-line usage:
echo   AgentRules.cmd check
echo   AgentRules.cmd preview
echo   AgentRules.cmd sync
echo   AgentRules.cmd codex
echo   AgentRules.cmd antigravity
echo   AgentRules.cmd build
echo   AgentRules.cmd test
echo   AgentRules.cmd help
echo.
echo Warning: sync, codex, and antigravity apply changes immediately.
goto exit_success

:usage_error
echo Usage: AgentRules.cmd [check^|preview^|sync^|codex^|antigravity^|build^|test^|help]
set "RESULT=2"
goto exit_result

:exit_with_result
set "RESULT=%ERRORLEVEL%"
goto exit_result

:exit_success
set "RESULT=0"

:exit_result
popd >nul
endlocal & exit /b %RESULT%
