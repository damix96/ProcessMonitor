@echo off
chcp 1251
:: BatchGotAdmin
:-------------------------------------
REM  --> ��������� ������� ���� ��������������
    net session >nul 2>&1
    if %errorLevel% == 0 (
        echo � ��� ���� ����� ��������������
    ) else (
        echo � ��� ��� ���� ��������������
    )
REM --> ���� ������ �� ����� 0, �� �� �����.
if '%errorlevel%' NEQ '0' (
    echo ������ � ���������� ����...
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
:: �������� ������� ����������
set "CURRENT_DIR=%~dp0"
echo ������� ����������: %CURRENT_DIR%
echo ������ ProcessMonitor.ps1...
echo.

:: ��������� PowerShell ������ � ����������� �����������
start powershell.exe -File "%CURRENT_DIR%ProcessMonitor.ps1" 