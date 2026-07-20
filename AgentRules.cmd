@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\AgentRules.Menu.ps1" %*
exit /b %ERRORLEVEL%
