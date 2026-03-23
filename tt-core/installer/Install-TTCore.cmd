@echo off
:: TT-Core Installer (TT-Production v14.0)
:: Right-click → Run as Administrator for best results.
:: ─────────────────────────────────────────────────────────────────

echo.
echo TT-Core Installer (TT-Production v14.0)
echo.

:: Check if PowerShell is available
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell not found.
    echo Install PowerShell from: https://microsoft.com/powershell
    pause
    exit /b 1
)

:: Run the PowerShell installer
:: To customize, pass parameters:
::   -RootPath "C:\my\path"
::   -WithTunnel -Domain "example.com"
::   -NoWordPress
::   -WithKanboard
::   -WithMonitoring
::   -WithPortainer
::   -WithQdrant
::   -WithOllama / -WithOpenWebUI
::   -NoStart (configure only, don't start)

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install-TTCore.ps1" %*

echo.
if errorlevel 1 (
    echo Installation encountered errors. Check output above.
) else (
    echo Installation complete. See output above for service URLs.
)
pause


