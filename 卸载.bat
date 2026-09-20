@echo off
rem Quartus II 13.1 zh-CN uninstaller entry (restore English originals)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
pause
