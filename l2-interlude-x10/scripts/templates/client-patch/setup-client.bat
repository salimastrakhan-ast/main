@echo off
rem ===========================================================================
rem  Настройка клиента Lineage 2 на подключение к серверу @ADDR@
rem  Двойной клик по этому файлу — всё остальное сделает patch.ps1.
rem ===========================================================================
chcp 65001 >nul
title Настройка клиента Lineage 2

where powershell >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Не найден PowerShell — впиши адрес в system\l2.ini вручную:
  echo.
  echo       [Server]
  echo       ServerAddr=@ADDR@
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" %*

echo.
pause
