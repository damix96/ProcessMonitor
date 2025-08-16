@echo off
chcp 1251
:: BatchGotAdmin
:-------------------------------------
REM  --> Проверяем наличие прав администратора
    net session >nul 2>&1
    if %errorLevel% == 0 (
        echo У вас есть права администратора
    ) else (
        echo У вас нет прав администратора
    )
REM --> Если ошибка не равна 0, мы не админ.
if '%errorlevel%' NEQ '0' (
    echo Запуск с повышением прав...
    goto UACPrompt
) else ( goto gotAdmin )
:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B
:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"
:--------------------------------------
:: Получаем текущую директорию
set "CURRENT_DIR=%~dp0"
echo Текущая директория: %CURRENT_DIR%
echo Запуск ProcessMonitor.ps1...
echo.

:: Запускаем PowerShell скрипт с правильными параметрами
start powershell.exe -File "%CURRENT_DIR%ProcessMonitor.ps1" 