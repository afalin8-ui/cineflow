@echo off
setlocal
cd /d "%~dp0"

if not exist "cinelight-bridge.js" goto nofile
where node >nul 2>nul
if errorlevel 1 goto nonode

echo Запускаю мост CineLight...
echo Если Windows спросит про доступ в сеть - разрешите,
echo иначе iPad не увидит мост.
echo.
node cinelight-bridge.js %*
echo.
echo Мост остановлен.
goto end

:nofile
echo.
echo   Рядом с этим файлом нет cinelight-bridge.js
echo   Положите оба файла в одну папку и запустите снова.
goto end

:nonode
echo.
echo   Не найден Node.js - без него мост не запустится.
echo.
echo   1. Откройте https://nodejs.org
echo   2. Скачайте версию LTS для Windows
echo   3. Установите (далее-далее-готово)
echo   4. ЗАКРОЙТЕ это окно и запустите файл заново
echo.
echo   Последний шаг обязателен: без перезапуска Windows
echo   ещё не знает про новую программу.
goto end

:end
echo.
pause
