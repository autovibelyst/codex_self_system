@echo off
pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Snapshot.ps1" %*
