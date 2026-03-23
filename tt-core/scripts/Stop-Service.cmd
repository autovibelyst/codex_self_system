@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Stop-Service.ps1" %*
