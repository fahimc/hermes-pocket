@echo off
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\ollama-model.ps1" -Root "%ROOT%" %*
exit /b %ERRORLEVEL%
