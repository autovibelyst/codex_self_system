@echo off
pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-BackupSchedule.ps1" %*
