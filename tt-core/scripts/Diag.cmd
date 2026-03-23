@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Diag.ps1" %*
