@echo off
chcp 936 >nul
title BATTLETECH 简体中文补丁 安装
cd /d "%~dp0"

echo.
echo  ================================================
echo   BATTLETECH / RogueTech 简体中文补丁 安装
echo  ================================================
echo.
echo   安装前请完全退出游戏（游戏运行时会占用模组文件）。
echo   安装过程约 3~4 分钟，请耐心等待。
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0工具\安装.ps1"
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
    echo  安装成功完成。
) else (
    echo  安装未完成（返回码 %RC%），请查看上方提示。
)
echo.
pause
