@echo off
:: Preflight-Check.cmd — TT-Core v6.7.5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Preflight-Check.ps1" %*
