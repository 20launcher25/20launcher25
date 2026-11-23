@echo off
rem Claude Code Launcher - repair: opens Claude Code with the repair prompt (REPAIR.md)
chcp 65001 >nul
set "DIR=%LOCALAPPDATA%\ClaudeCodeLauncher"
if not exist "%DIR%\REPAIR.md" set "DIR=%~dp0"
if not exist "%DIR%\REPAIR.md" (
  echo.
  echo  [X] Не найден REPAIR.md ни в %LOCALAPPDATA%\ClaudeCodeLauncher, ни рядом с Repair.cmd.
  echo      Распакуйте архив лаунчера заново и запустите Repair.cmd из этой папки.
  echo  REPAIR.md is missing. Unpack the launcher archive again and run Repair.cmd from it.
  echo.
  pause
  exit /b 1
)
cd /d "%DIR%"
where claude >nul 2>nul
if errorlevel 1 (
  echo.
  echo  [X] Claude Code не установлен или его нет в PATH.
  echo      Установите: powershell -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
  echo      и откройте Repair.cmd снова.
  echo  Claude Code is not installed or not in PATH. Install it with the command above.
  echo.
  pause
  exit /b 1
)
claude "Read REPAIR.md in this folder and follow it: find out what is broken in Claude Code Launcher on this computer, fix it and verify the fix."
