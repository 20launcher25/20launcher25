@echo off
rem Claude Code Launcher - uninstall
chcp 65001 >nul
set "SCRIPT=%LOCALAPPDATA%\ClaudeCodeLauncher\launcher.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0launcher.ps1"
if not exist "%SCRIPT%" (
  echo.
  echo  [X] Лаунчер не найден ни в %LOCALAPPDATA%\ClaudeCodeLauncher, ни рядом с Uninstall.cmd.
  echo      Похоже, он уже удалён. Ярлыки, если остались, можно просто удалить.
  echo.
  echo  The launcher was not found; it seems to be uninstalled already.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Uninstall
