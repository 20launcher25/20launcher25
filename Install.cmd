@echo off
rem Claude Code Launcher - install
chcp 65001 >nul
if not exist "%~dp0launcher.ps1" (
  echo.
  echo  [X] Не найден launcher.ps1 рядом с Install.cmd:
  echo      %~dp0
  echo.
  echo  Распакуйте архив лаунчера целиком в одну папку ^(не запускайте Install.cmd из архива^)
  echo  и запустите Install.cmd снова.
  echo.
  echo  launcher.ps1 is missing next to Install.cmd. Unpack the whole archive into one folder and try again.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1" -Install
if errorlevel 1 (
  echo.
  echo  [!] Установка завершилась с ошибкой. Текст ошибки выше. Помочь может Repair.cmd.
  echo      Setup failed - see the error above. Repair.cmd can help.
  pause
)
