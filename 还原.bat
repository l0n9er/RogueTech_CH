@echo off
chcp 936 >nul
title BATTLETECH 简体中文补丁 还原
cd /d "%~dp0"

echo.
echo  ================================================
echo   BATTLETECH / RogueTech 简体中文补丁 还原
echo  ================================================
echo.
echo   还原会用 backup\ 下最新的备份覆盖游戏文件。
echo   还原前请完全退出游戏（游戏运行时会占用模组文件）。
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0工具\还原.ps1" %*
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
    echo  还原成功完成。
) else (
    echo  还原未完成（返回码 %RC%），请查看上方提示。
)
echo.
pause
