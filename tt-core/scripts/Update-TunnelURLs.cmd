@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Update-TunnelURLs.ps1" %*
