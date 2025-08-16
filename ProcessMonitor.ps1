# ProcessMonitor.ps1 - Elegant Process Handler System
# Автоматический мониторинг процессов на основе пользовательских скриптов
#
# Версия: 2.0.0
# Автор: Process Monitor Team
# Создано: 2025
#
# ОПИСАНИЕ:
# Система автоматического мониторинга процессов, которая выполняет пользовательские 
# скрипты при запуске и завершении указанных процессов. Обработчики помещаются в папку
# ProcessHandlers, а система автоматически начинает их отслеживать.
#
# ИСПОЛЬЗОВАНИЕ:
# .\ProcessMonitor.ps1
#
# ТРЕБОВАНИЯ:
# - Windows PowerShell 5.1+ или PowerShell Core 6.0+
# - Права на выполнение скриптов (ExecutionPolicy)
# - Опционально: права администратора для WMI событий и автозагрузки

#region ═══════════════════════════════════════════════════════════════════════════════════
#region                            🔧 КОНФИГУРАЦИЯ                                         
#region ═══════════════════════════════════════════════════════════════════════════════════

# Основные настройки
$SCRIPT_VERSION = "2.0.0"
$SCRIPT_TITLE = "Process Monitor - Elegant Edition"
$HANDLERS_FOLDER = "ProcessHandlers"
$ENABLE_AUTOSTART = $true    # Предлагать добавление в автозагрузку
$ENABLE_EXAMPLES = $true     # Создавать папку с примерами

# Модули для загрузки
$REQUIRED_MODULES = @(
    "ServiceFunctions.ps1",
    "ExamplesGenerator.ps1", 
    "MonitoringEngine.ps1"
)

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                         КОНЕЦ СЕКЦИИ КОНФИГУРАЦИИ                              
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                          📦 ЗАГРУЗКА МОДУЛЕЙ                                       
#region ═══════════════════════════════════════════════════════════════════════════════════
Set-Location $PSScriptRoot
$scriptDir = Split-Path $PSCommandPath -Parent
foreach ($module in $REQUIRED_MODULES) {
    $modulePath = Join-Path $scriptDir $module

    if (-not (Test-Path $modulePath)) {
        Write-Host "❌ Модуль не найден: $module"
        continue
    }

    Write-Host "⚡ Загружаем: $modulePath"
    . $modulePath
}


#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                       КОНЕЦ СЕКЦИИ ЗАГРУЗКИ МОДУЛЕЙ                            
#endregion ═══════════════════════════════════════════════════════════════════════════════
# --- Добавляем функции WinAPI для управления окном ---
# --- Добавляем функции WinAPI для управления окном ---
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WinAPI {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# --- Функции для удобства ---
function Hide-Console {
    $hwnd = [WinAPI]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        [WinAPI]::ShowWindow($hwnd, 0) # 0 = SW_HIDE
    }
}

function Hide-ConsoleDelayed {
    param(
        [int]$DelaySeconds = 2
    )

    # HWND текущей консоли (передаем в фон, чтобы скрыть именно ЭТО окно)
    $hwnd = [WinAPI]::GetConsoleWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return }
    $hwndVal = $hwnd.ToInt64()

    $scriptBlock = {
        param($Delay, $HwndInt64)
        Start-Sleep -Seconds $Delay

        # user32 в фоновой сессии
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWin {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

        [IntPtr]$ptr = [IntPtr]::new([long]$HwndInt64)
        [NativeWin]::ShowWindow($ptr, 0) | Out-Null   # 0 = SW_HIDE
    }

    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
        Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList $DelaySeconds, $hwndVal | Out-Null
    }
    else {
        Start-Job -ScriptBlock $scriptBlock -ArgumentList $DelaySeconds, $hwndVal | Out-Null
    }
}

function Show-Console {
    $hwnd = [WinAPI]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        [WinAPI]::ShowWindow($hwnd, 5) # 5 = SW_SHOW
    }
}



#region ═══════════════════════════════════════════════════════════════════════════════════
#region                         🎯 ИНИЦИАЛИЗАЦИЯ СИСТЕМЫ                                   
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Выполняет полную инициализацию системы Process Monitor.

.DESCRIPTION
Проверяет системные требования, создает необходимые папки, генерирует примеры
и выполняет все подготовительные действия.

.OUTPUTS
[bool] - True если инициализация прошла успешно
#>
function Initialize-ProcessMonitor {
    Write-LogSeparator -Title "ИНИЦИАЛИЗАЦИЯ PROCESS MONITOR v$SCRIPT_VERSION"
    
    # 1. Проверяем ExecutionPolicy
    Write-LogMessage "🔍 Проверка политики выполнения..." -Color Cyan
    

    if (-not (Test-ExecutionPolicy)) {
        Write-LogMessage "⚠️ Рекомендуется настроить ExecutionPolicy" -Color Yellow
            
        $choice = Read-Host "Настроить ExecutionPolicy автоматически? (Y/N)"
        if ($choice -match '^[Yy]') {
            if (Set-ExecutionPolicyIfNeeded) {
                Write-LogMessage "✅ ExecutionPolicy настроена" -Color Green
            }
            else {
                Write-LogMessage "⚠️ Не удалось настроить ExecutionPolicy автоматически" -Color Yellow
            }
        }
    }

    
    # 2. Проверяем и запрашиваем права администратора
    Write-LogMessage "🔐 Проверка прав доступа..." -Color Cyan
    $isAdmin = Test-AdminRights
    
    if (-not $isAdmin) {
        Request-AdminRights
    } 
    else {
        Write-LogMessage "✅ Запущен с правами администратора" -Color Green
    }
    
    # 3. Проверяем дублирование и завершаем старые экземпляры
    Write-LogMessage "🔒 Проверка дублирования экземпляров..." -Color Cyan
    try {
        $terminated = Stop-ExistingScript -ScriptPath $PSCommandPath
            
        if ($terminated -gt 0) {
            Write-LogMessage "✅ Завершено экземпляров: $terminated" -Color Green
        }
    }
    catch {
        Write-LogMessage "⚠️ Ошибка проверки дублирования: $_" -Color Yellow
    }
    
    # 4. Создаем структуру папок и примеров
    if ($ENABLE_EXAMPLES) {
        Write-LogMessage "📁 Инициализация структуры примеров..." -Color Cyan
        try {
            $result = Initialize-ExamplesStructure -HandlersPath $HANDLERS_FOLDER
            
            if ($result.CreatedFolders.Count -gt 0 -or $result.CreatedFiles.Count -gt 0) {
                Write-LogMessage "✅ Структура примеров создана" -Color Green
            }
            else {
                Write-LogMessage "ℹ️ Структура примеров уже существует" -Color Blue
            }
        }
        catch {
            Write-LogMessage "⚠️ Не удалось создать примеры: $_" -Color Yellow
        }
    }
    
    # 5. Настраиваем автозагрузку
    if ($ENABLE_AUTOSTART -and (Test-AdminRights)) {
        Write-LogMessage "🚀 Настройка автозагрузки..." -Color Cyan
        
        try {
            if (-not (Test-InStartup -ScriptPath $PSCommandPath)) {
                $choice = Read-Host "Добавить Process Monitor в автозагрузку? (Y/N)"
                if ($choice -match '^[Yy]') {
                    if (Add-ToStartup -ScriptPath $PSCommandPath) {
                        Write-LogMessage "✅ Process Monitor добавлен в автозагрузку" -Color Green
                    }
                    else {
                        Write-LogMessage "⚠️ Не удалось добавить в автозагрузку" -Color Yellow
                    }
                }
            }
            else {
                Write-LogMessage "ℹ️ Process Monitor уже в автозагрузке" -Color Blue
            }
        }
        catch {
            Write-LogMessage "⚠️ Ошибка настройки автозагрузки: $_" -Color Yellow
        }
    }
    else {
        if ($ENABLE_AUTOSTART) {
            Write-LogMessage "ℹ️ Автозагрузка доступна только с правами администратора" -Color Blue
        }
    }
    
    return $true
}

<#
.SYNOPSIS
Отображает приветственное сообщение и информацию о системе.

.DESCRIPTION
Показывает красивое приветствие с информацией о версии, возможностях и состоянии системы.
#>
function Show-WelcomeMessage {
    $isAdmin = Test-AdminRights
    $adminStatus = if ($isAdmin) { "Администратор" } else { "Пользователь" }
    $handlersPath = Join-Path (Split-Path $PSCommandPath -Parent) $HANDLERS_FOLDER
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║               🎯 PROCESS MONITOR v$SCRIPT_VERSION                " -ForegroundColor Cyan
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║  Автоматический мониторинг процессов на основе             " -ForegroundColor Cyan
    Write-Host "║  пользовательских скриптов                                 " -ForegroundColor Cyan
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║  📁 Папка обработчиков: $($HANDLERS_FOLDER.PadRight(32)) " -ForegroundColor Cyan
    Write-Host "║  🔐 Режим работы: $($adminStatus.PadRight(37)) " -ForegroundColor Cyan
    Write-Host "║  📝 Создание примеров: $(if ($ENABLE_EXAMPLES) { 'Включено'.PadRight(31) } else { 'Отключено'.PadRight(30) }) " -ForegroundColor Cyan
    Write-Host "║  🚀 Автозагрузка: $(if ($ENABLE_AUTOSTART) { 'Включена'.PadRight(35) } else { 'Отключена'.PadRight(34) }) " -ForegroundColor Cyan
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║  💡 КАК ИСПОЛЬЗОВАТЬ:                                      " -ForegroundColor Yellow
    Write-Host "║     1. Поместите .ps1 файлы в папку $HANDLERS_FOLDER            " -ForegroundColor White
    Write-Host "║     2. Назовите файл по имени процесса (например: notepad.ps1) " -ForegroundColor White
    Write-Host "║     3. Process Monitor автоматически начнет мониторинг     " -ForegroundColor White
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║  🔧 ТИПЫ ОБРАБОТЧИКОВ:                                    " -ForegroundColor Yellow
    Write-Host "║     • processName.ps1 - запуск И завершение               " -ForegroundColor White
    Write-Host "║     • start.processName.ps1 - только запуск               " -ForegroundColor White
    Write-Host "║     • end.processName.ps1 - только завершение             " -ForegroundColor White
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║  📚 Примеры и документация в папке: $HANDLERS_FOLDER\_examples   " -ForegroundColor Green
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "║  ⏹️  Для остановки нажмите Ctrl+C                         " -ForegroundColor Yellow
    Write-Host "║                                                            " -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                     КОНЕЦ СЕКЦИИ ИНИЦИАЛИЗАЦИИ СИСТЕМЫ                         
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                             🚀 ГЛАВНАЯ ФУНКЦИЯ                                     
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Главная функция Process Monitor.

.DESCRIPTION
Выполняет полную инициализацию и запускает систему мониторинга процессов.
Обрабатывает все этапы от загрузки модулей до запуска основного цикла.

.OUTPUTS
[int] - Код возврата (0 - успех, 1 - ошибка)
#>
function Main {
    # Устанавливаем заголовок консоли
    $Host.UI.RawUI.WindowTitle = $SCRIPT_TITLE
    
    Show-WelcomeMessage
    
    # Инициализируем систему
    Write-LogMessage "🔧 Запуск инициализации системы..." -Color Cyan
    if (-not (Initialize-ProcessMonitor)) {
        Write-LogMessage "💥 Критическая ошибка инициализации" -Color Red
        Read-Host "Нажмите Enter для выхода"
        return 1
    }
    
    # Устанавливаем обработчик Ctrl+C для корректного завершения
    try {
        $null = [Console]::TreatControlCAsInput = $false
        [Console]::CancelKeyPress += {
            param($sender, $e)
            $e.Cancel = $true
            Write-LogMessage "🛑 Получен сигнал остановки..." -Color Yellow
            if ($global:MonitoringConfig) {
                $global:MonitoringConfig.IsRunning = $false
            }
            throw [System.Management.Automation.PipelineStoppedException]::new()
        }
    }
    catch {
        # Продолжаем без обработчика если не удается установить
    }
    Hide-ConsoleDelayed -DelaySeconds 5
    # Запускаем основной мониторинг
    try {
        Write-LogSeparator -Title "ЗАПУСК МОНИТОРИНГА"
        
        if (Get-Command Start-ProcessMonitoring -ErrorAction SilentlyContinue) {
            $success = Start-ProcessMonitoring -HandlersPath $HANDLERS_FOLDER
            
            if ($success) {
                Write-LogMessage "✅ Мониторинг завершен штатно" -Color Green
                return 0
            }
            else {
                Write-LogMessage "❌ Мониторинг завершен с ошибками" -Color Red
                return 1
            }
        }
        else {
            Write-LogMessage "❌ Функция мониторинга недоступна (MonitoringEngine не загружен)" -Color Red
            return 1
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-LogMessage "🛑 Мониторинг остановлен пользователем" -Color Yellow
        return 0
    }
    catch {
        Write-LogMessage "💥 Критическая ошибка мониторинга: $_" -Color Red
        return 1
    }
    finally {
        # Финальная очистка
        try {
            if (Get-Command Release-ScriptMutex -ErrorAction SilentlyContinue) {
                Release-ScriptMutex
            }
            
            if (Get-Command Stop-ProcessMonitoring -ErrorAction SilentlyContinue) {
                Stop-ProcessMonitoring
            }
            
            Write-LogSeparator -Title "ЗАВЕРШЕНИЕ РАБОТЫ"
            Write-LogMessage "🏁 Process Monitor завершен" -Color Cyan
        }
        catch {
            Write-LogMessage "⚠️ Ошибка финальной очистки: $_" -Color Yellow
        }
    }
    
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                          КОНЕЦ ГЛАВНОЙ ФУНКЦИИ                                 
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                              🎬 ТОЧКА ВХОДА                                        
#region ═══════════════════════════════════════════════════════════════════════════════════

# Простые fallback функции для случая если модули не загружены
function Write-LogMessage {
    param(
        [string]$Message, 
        [ConsoleColor]$Color = "White",
        [switch]$NoTimestamp
    )
    
    $timestamp = if ($NoTimestamp) { "" } else { "[$(Get-Date -Format 'HH:mm:ss')] " }
    Write-Host "$timestamp$Message" -ForegroundColor $Color
}

function Write-LogSeparator {
    param([string]$Title = "", [ConsoleColor]$Color = "Cyan")
    
    if ($Title) {
        $separator = "═" * 20 + " $Title " + "═" * (40 - $Title.Length)
    }
    else {
        $separator = "═" * 60
    }
    Write-Host $separator -ForegroundColor $Color
}

function Test-AdminRights {
    try {
        $currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    }
    catch {
        return $false
    }
}

# 🎬 ЗАПУСК СКРИПТА
# Проверяем что скрипт запущен напрямую, а не через dot-sourcing
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $exitCode = Main
        exit $exitCode
    }
    catch {
        Write-Host "💥 Неожиданная ошибка: $_" -ForegroundColor Red
        Write-Host "🐛 Trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }
}
else {
    Write-LogMessage "ℹ️ ProcessMonitor.ps1 загружен через dot-sourcing" -Color Blue -NoTimestamp
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                           КОНЕЦ ТОЧКИ ВХОДА                                    
#endregion ═══════════════════════════════════════════════════════════════════════════════

# 
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# ░                                                                                        ░
# ░  🎯 PROCESS MONITOR v2.0.0 - ELEGANT EDITION                                          ░
# ░                                                                                        ░ 
# ░  Создан для автоматизации реакций на события процессов                                ░
# ░  Простой в использовании, мощный в возможностях                                       ░
# ░                                                                                        ░
# ░  Спасибо за использование Process Monitor! 🚀                                         ░
# ░                                                                                        ░
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░