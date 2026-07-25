@echo off
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   Нужен Node.js. Скачайте установщик LTS с https://nodejs.org,
  echo   установите его (далее-далее-готово) и запустите этот файл снова.
  echo.
  pause
  exit /b
)
node cinelight-bridge.js %*
pause
