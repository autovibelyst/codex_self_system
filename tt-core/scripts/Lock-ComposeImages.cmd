@echo off
:: Lock-ComposeImages.cmd — TT-Core v6.7.5
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Lock-ComposeImages.ps1" %*
