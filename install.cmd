@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "intent_compiler_exit=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %intent_compiler_exit%
