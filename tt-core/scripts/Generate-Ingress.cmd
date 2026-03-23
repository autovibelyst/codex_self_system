@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Generate-Ingress.ps1" %*
