@echo off
setlocal
cd /d "%~dp0"

if not exist "cinelight-export.js" goto nofile
where node >nul 2>nul
if errorlevel 1 goto nonode

echo Собираю папку для отдельного репозитория CineLight...
echo.
node cinelight-export.js
goto end

:nofile
echo.
echo   Рядом с этим файлом нет cinelight-export.js
echo   Положите оба файла в одну папку и запустите снова.
goto end

:nonode
echo.
echo   Не найден Node.js - без него сборка не запустится.
echo   Поставьте его с https://nodejs.org (версия LTS),
echo   закройте это окно и запустите файл заново.
goto end

:end
echo.
pause
