@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PORTABLE_ROOT=%~dp0"
if "%PORTABLE_ROOT:~-1%"=="\" set "PORTABLE_ROOT=%PORTABLE_ROOT:~0,-1%"
set "HERMES_HOME=%PORTABLE_ROOT%\data"
set "RUNTIME_DIR=%PORTABLE_ROOT%\.cache\runtimes\windows-x64"
set "SOURCE_DIR=%PORTABLE_ROOT%\src\hermes-agent"
set "VENV_DIR=%RUNTIME_DIR%\venv"
set "PYTHON_EXE=%VENV_DIR%\Scripts\python.exe"

if not exist "%RUNTIME_DIR%\ready.flag" (
    echo.
    echo Hermes Pocket first-run setup
    echo This downloads portable runtimes and Hermes dependencies into this folder.
    echo.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PORTABLE_ROOT%\scripts\setup-windows.ps1" -Root "%PORTABLE_ROOT%"
    if errorlevel 1 (
        echo.
        echo Setup failed. Review the error above and run launch.bat again.
        pause
        exit /b 1
    )
)

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Portable Python environment is missing. Delete .cache and retry setup.
    pause
    exit /b 1
)
if not exist "%SOURCE_DIR%\hermes_cli" (
    echo [ERROR] Hermes source is missing. Delete .cache and src, then retry setup.
    pause
    exit /b 1
)

set "VIRTUAL_ENV=%VENV_DIR%"
set "PATH=%VENV_DIR%\Scripts;%RUNTIME_DIR%\python;%RUNTIME_DIR%\python\Scripts;%RUNTIME_DIR%\node;%RUNTIME_DIR%\node\bin;%RUNTIME_DIR%\uv;%RUNTIME_DIR%\bin;%RUNTIME_DIR%\git\cmd;%RUNTIME_DIR%\git\bin;%PATH%"
set "PYTHONNOUSERSITE=1"
set "PYTHONHOME="
set "PYTHONPATH="
set "UV_NO_CONFIG=1"
set "UV_PYTHON=%RUNTIME_DIR%\python\python.exe"
set "UV_CACHE_DIR=%PORTABLE_ROOT%\.cache\uv"
set "PLAYWRIGHT_BROWSERS_PATH=%RUNTIME_DIR%\playwright"
set "APPDATA=%PORTABLE_ROOT%\.cache\windows-appdata"
set "LOCALAPPDATA=%PORTABLE_ROOT%\.cache\windows-localappdata"
set "HOMEDRIVE="
set "HOMEPATH="
set "USERPROFILE=%PORTABLE_ROOT%\.cache\windows-userprofile"

if not "%~1"=="" (
    "%PYTHON_EXE%" -m hermes_cli.main %*
) else (
    "%PYTHON_EXE%" -m hermes_cli.main
)
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%
