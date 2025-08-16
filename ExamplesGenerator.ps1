# ExamplesGenerator.ps1 - Process Monitor Examples Generator
# Генератор примеров и шаблонов скриптов для ProcessMonitor
#
# Создает папку _examples с подробными примерами обработчиков процессов
# Показывает какие параметры передаются в пользовательские скрипты
# 
# Использование:
# . "ExamplesGenerator.ps1"
# Initialize-ExamplesStructure -HandlersPath "ProcessHandlers"

#region ═══════════════════════════════════════════════════════════════════════════════════
#region                          📁 СОЗДАНИЕ СТРУКТУРЫ                                     
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Инициализирует структуру папок и создает примеры скриптов.

.DESCRIPTION
Создает папку ProcessHandlers и подпапку _examples с шаблонами обработчиков процессов.

.PARAMETER HandlersPath
Путь к папке с обработчиками. По умолчанию "ProcessHandlers".

.PARAMETER Force
Принудительно пересоздать примеры, даже если они уже существуют.

.EXAMPLE
Initialize-ExamplesStructure

.EXAMPLE
Initialize-ExamplesStructure -HandlersPath "MyHandlers" -Force

.OUTPUTS
[PSCustomObject] - Информация о созданных файлах и папках
#>
function Initialize-ExamplesStructure {
    param(
        [string]$HandlersPath = "ProcessHandlers",
        [switch]$Force
    )
    
    $result = [PSCustomObject]@{
        HandlersPath   = ""
        ExamplesPath   = ""
        CreatedFolders = @()
        CreatedFiles   = @()
        UpdatedFiles   = @()
        Errors         = @()
    }
    
    try {
        # Определяем базовую папку относительно текущего скрипта
        $scriptDir = Split-Path $PSCommandPath -Parent
        $fullHandlersPath = Join-Path $scriptDir $HandlersPath
        $examplesPath = Join-Path $fullHandlersPath "_examples"
        
        $result.HandlersPath = $fullHandlersPath
        $result.ExamplesPath = $examplesPath
        
        # Создаем папку обработчиков
        if (-not (Test-Path $fullHandlersPath)) {
            New-Item -ItemType Directory -Path $fullHandlersPath -Force | Out-Null
            $result.CreatedFolders += $HandlersPath
            Write-LogMessage "📁 Создана папка: $HandlersPath" -Color Cyan
        }
        
        # Создаем папку примеров
        if (-not (Test-Path $examplesPath)) {
            New-Item -ItemType Directory -Path $examplesPath -Force | Out-Null
            $result.CreatedFolders += "_examples"
            Write-LogMessage "📁 Создана папка: $HandlersPath\_examples" -Color Cyan
        }
        
        # Создаем файлы примеров
        $exampleFiles = Create-ExampleFiles -ExamplesPath $examplesPath -Force:$Force
        $result.CreatedFiles = $exampleFiles.Created
        $result.UpdatedFiles = $exampleFiles.Updated
        
        # Создаем README файл
        $readmeCreated = Create-ReadmeFile -ExamplesPath $examplesPath -Force:$Force
        if ($readmeCreated.Created) {
            $result.CreatedFiles += "README.md"
        }
        if ($readmeCreated.Updated) {
            $result.UpdatedFiles += "README.md"
        }
        
        # Итоговая статистика
        if ($result.CreatedFiles.Count -gt 0 -or $result.UpdatedFiles.Count -gt 0) {
            Write-LogMessage "✅ Структура примеров инициализирована" -Color Green
            Write-LogMessage "📝 Создано файлов: $($result.CreatedFiles.Count)" -Color Blue
            if ($result.UpdatedFiles.Count -gt 0) {
                Write-LogMessage "🔄 Обновлено файлов: $($result.UpdatedFiles.Count)" -Color Yellow
            }
            Write-LogMessage "💡 Посмотрите папку $HandlersPath\_examples для изучения!" -Color Cyan
        }
        else {
            Write-LogMessage "ℹ️ Примеры уже существуют и актуальны" -Color Blue
        }
        
        return $result
    }
    catch {
        $error = "Ошибка инициализации: $_"
        $result.Errors += $error
        Write-LogMessage "❌ $error" -Color Red
        return $result
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                      КОНЕЦ СЕКЦИИ СОЗДАНИЯ СТРУКТУРЫ                           
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                         📝 ГЕНЕРАЦИЯ ПРИМЕРОВ                                      
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Создает файлы примеров обработчиков процессов.

.DESCRIPTION
Генерирует подробные примеры скриптов с документацией и примерами использования.

.PARAMETER ExamplesPath
Путь к папке примеров.

.PARAMETER Force
Принудительно пересоздать файлы, даже если они существуют.

.OUTPUTS
[PSCustomObject] - Информация о созданных и обновленных файлах
#>
function Create-ExampleFiles {
    param(
        [string]$ExamplesPath,
        [switch]$Force
    )
    
    $result = [PSCustomObject]@{
        Created = @()
        Updated = @()
        Skipped = @()
    }
    
    # Получаем шаблоны примеров
    $examples = Get-ExampleTemplates
    
    foreach ($example in $examples.GetEnumerator()) {
        $fileName = $example.Key
        $content = $example.Value
        $filePath = Join-Path $ExamplesPath $fileName
        
        try {
            if ((Test-Path $filePath) -and -not $Force) {
                $result.Skipped += $fileName
                continue
            }
            
            $content | Out-File -FilePath $filePath -Encoding UTF8 -Force
            
            if (Test-Path $filePath) {
                if ($Force -and (Get-Item $filePath).Length -gt 0) {
                    $result.Updated += $fileName
                    Write-LogMessage "🔄 Обновлен: $fileName" -Color Yellow
                }
                else {
                    $result.Created += $fileName
                    Write-LogMessage "📝 Создан: $fileName" -Color Green
                }
            }
        }
        catch {
            Write-LogMessage "❌ Ошибка создания $fileName`: $_" -Color Red
        }
    }
    
    return $result
}

<#
.SYNOPSIS
Возвращает шаблоны примеров обработчиков.

.DESCRIPTION
Генерирует содержимое файлов-примеров с подробными комментариями и примерами кода.

.OUTPUTS
[hashtable] - Словарь с именами файлов и их содержимым
#>
function Get-ExampleTemplates {
    $templates = @{}
    
    # Универсальный обработчик
    $templates["processName.ps1"] = @"
# ═══════════════════════════════════════════════════════════════════════════════════════
# УНИВЕРСАЛЬНЫЙ ОБРАБОТЧИК ПРОЦЕССА
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# Файл: processName.ps1 (замените processName на реальное имя процесса, например notepad.ps1)
# 
# НАЗНАЧЕНИЕ:
# Этот скрипт вызывается при ЛЮБОМ событии процесса (запуск И завершение)
# Определяет тип события через параметр `$Action
#
# КОГДА ИСПОЛЬЗУЕТСЯ:
# - Когда нужна единая логика для обработки запуска и завершения
# - Для универсальных действий (логирование, уведомления, мониторинг)
# - Когда логика запуска и завершения связана между собой

#region Параметры скрипта
param(
    [string]`$ProcessName,      # Имя процесса без расширения .exe (например: "notepad")
    [int]`$ProcessId,           # Уникальный идентификатор процесса (PID)
    [string]`$Action,           # Тип события: "Started" или "Stopped"
    [datetime]`$Timestamp,      # Точное время события
    [string]`$ExecutablePath    # Полный путь к исполняемому файлу (если доступен)
)
#endregion

#region Основная логика
# Логирование события с временной меткой
Write-Host "[`$(Get-Date -Format 'HH:mm:ss')] `$Action процесса `$ProcessName (PID: `$ProcessId)" -ForegroundColor Cyan

# Основная логика в зависимости от типа события
switch (`$Action) {
    "Started" {
        #region Действия при ЗАПУСКЕ процесса
        Write-Host "🟢 Процесс `$ProcessName запущен!" -ForegroundColor Green
        Write-Host "   📁 Путь: `$ExecutablePath" -ForegroundColor Gray
        Write-Host "   🆔 PID: `$ProcessId" -ForegroundColor Gray
        Write-Host "   ⏰ Время: `$(`$Timestamp.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Gray
        
        # ═══ ПРИМЕРЫ ДЕЙСТВИЙ ПРИ ЗАПУСКЕ ═══
        
        # 📝 Логирование в файл
        # "`$(Get-Date): STARTED - `$ProcessName (PID: `$ProcessId)" | Add-Content "C:\Logs\process_monitor.log"
        
        # 🔔 Уведомления пользователя
        # [System.Windows.Forms.MessageBox]::Show("Процесс `$ProcessName запущен!", "Process Monitor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        
        # 🌐 HTTP запросы к внешним сервисам
        # try {
        #     `$body = @{ process = `$ProcessName; action = "started"; pid = `$ProcessId; timestamp = `$Timestamp } | ConvertTo-Json
        #     Invoke-RestMethod -Uri "https://your-api.com/process-events" -Method POST -Body `$body -ContentType "application/json"
        # } catch { Write-Warning "Ошибка отправки уведомления: `$_" }
        
        # ⚙️ Изменение приоритета процесса
        # try {
        #     `$process = Get-Process -Id `$ProcessId -ErrorAction Stop
        #     `$process.PriorityClass = "High"
        #     Write-Host "✅ Приоритет процесса изменен на High" -ForegroundColor Green
        # } catch { Write-Warning "Не удалось изменить приоритет: `$_" }
        
        # 📂 Создание рабочей папки для процесса
        # `$workingDir = "C:\ProcessWorkspace\`$ProcessName"
        # if (-not (Test-Path `$workingDir)) {
        #     New-Item -ItemType Directory -Path `$workingDir -Force | Out-Null
        #     Write-Host "📁 Создана рабочая папка: `$workingDir" -ForegroundColor Cyan
        # }
        
        # 🚀 Запуск дополнительных программ или сервисов
        # if (`$ProcessName -eq "notepad") {
        #     Start-Process "calc" -WindowStyle Minimized
        #     Write-Host "🧮 Запущен калькулятор для работы с Notepad" -ForegroundColor Blue
        # }
        #endregion
    }
    
    "Stopped" {
        #region Действия при ЗАВЕРШЕНИИ процесса
        Write-Host "🔴 Процесс `$ProcessName завершен!" -ForegroundColor Red
        Write-Host "   🆔 PID был: `$ProcessId" -ForegroundColor Gray
        Write-Host "   ⏰ Время завершения: `$(`$Timestamp.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Gray
        
        # ═══ ПРИМЕРЫ ДЕЙСТВИЙ ПРИ ЗАВЕРШЕНИИ ═══
        
        # 📝 Логирование завершения
        # "`$(Get-Date): STOPPED - `$ProcessName (PID: `$ProcessId)" | Add-Content "C:\Logs\process_monitor.log"
        
        # 🧹 Очистка временных файлов
        # `$tempPath = "`$env:TEMP\`$ProcessName*"
        # Get-ChildItem `$tempPath -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse
        # Write-Host "🗑️ Временные файлы `$ProcessName очищены" -ForegroundColor Yellow
        
        # 📊 Сохранение статистики работы
        # `$stats = @{
        #     ProcessName = `$ProcessName
        #     PID = `$ProcessId
        #     StoppedAt = `$Timestamp
        #     Session = `$env:SESSIONNAME
        # }
        # `$stats | ConvertTo-Json | Add-Content "C:\Stats\process_stats.json"
        
        # 📦 Архивирование логов
        # `$logPath = "C:\Logs\`$ProcessName.log"
        # if (Test-Path `$logPath) {
        #     `$archivePath = "C:\Logs\Archive\`$ProcessName_`$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        #     Move-Item `$logPath `$archivePath -Force
        #     Write-Host "📦 Лог архивирован: `$archivePath" -ForegroundColor Cyan
        # }
        
        # 🛑 Остановка связанных процессов
        # if (`$ProcessName -eq "notepad") {
        #     Get-Process "calc" -ErrorAction SilentlyContinue | Stop-Process -Force
        #     Write-Host "🛑 Калькулятор остановлен вместе с Notepad" -ForegroundColor Yellow
        # }
        
        # 🔔 Уведомление о завершении длительного процесса
        # `$runTime = `$Timestamp - (Get-Process -Id `$ProcessId -ErrorAction SilentlyContinue).StartTime
        # if (`$runTime.TotalMinutes -gt 30) {
        #     [System.Windows.Forms.MessageBox]::Show("Процесс `$ProcessName работал `$([Math]::Round(`$runTime.TotalMinutes, 1)) минут", "Длительная сессия")
        # }
        #endregion
    }
}
#endregion

#region Общие действия (выполняются при любом событии)
# Здесь можно разместить код, который должен выполняться независимо от типа события

# Пример: обновление счетчика событий
# `$counterFile = "C:\Stats\`$ProcessName`_counter.txt"
# if (Test-Path `$counterFile) {
#     `$counter = [int](Get-Content `$counterFile) + 1
# } else {
#     `$counter = 1
# }
# `$counter | Out-File `$counterFile

# Пример: отправка телеметрии
# `$telemetry = @{
#     process = `$ProcessName
#     action = `$Action
#     timestamp = `$Timestamp
#     machine = `$env:COMPUTERNAME
#     user = `$env:USERNAME
# }
# Invoke-RestMethod -Uri "https://telemetry.example.com/events" -Method POST -Body (`$telemetry | ConvertTo-Json) -ContentType "application/json" -ErrorAction SilentlyContinue
#endregion

# ═══════════════════════════════════════════════════════════════════════════════════════
# ПОЛЕЗНЫЕ СОВЕТЫ:
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# 1. 🔍 ОТЛАДКА: Используйте Write-Host для вывода отладочной информации
# 2. 🛡️ БЕЗОПАСНОСТЬ: Всегда используйте try-catch для внешних операций
# 3. ⚡ ПРОИЗВОДИТЕЛЬНОСТЬ: Избегайте долгих операций в обработчиках
# 4. 📝 ЛОГИРОВАНИЕ: Ведите подробные логи для диагностики проблем
# 5. 🔄 ИДЕМПОТЕНТНОСТЬ: Операции должны быть безопасными для повторного выполнения
# 6. 🎯 СПЕЦИФИЧНОСТЬ: Используйте имя процесса для создания специфичной логики
#
# ═══════════════════════════════════════════════════════════════════════════════════════
"@

    # Обработчик только запуска
    $templates["start.processName.ps1"] = @"
# ═══════════════════════════════════════════════════════════════════════════════════════
# ОБРАБОТЧИК ЗАПУСКА ПРОЦЕССА
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# Файл: start.processName.ps1 (замените processName на реальное имя, например start.notepad.ps1)
#
# НАЗНАЧЕНИЕ:
# Этот скрипт вызывается ТОЛЬКО при запуске процесса
# Не вызывается при завершении процесса
#
# КОГДА ИСПОЛЬЗОВАТЬ:
# - Инициализация окружения для процесса
# - Настройка параметров запуска
# - Запуск сопутствующих сервисов
# - Проверка лицензий и зависимостей
# - Подготовка рабочих папок и файлов

#region Параметры скрипта
param(
    [string]`$ProcessName,      # Имя процесса без .exe (например: "notepad")
    [int]`$ProcessId,           # PID запущенного процесса  
    [string]`$Action,           # Всегда будет "Started" для этого типа обработчика
    [datetime]`$Timestamp,      # Точное время запуска процесса
    [string]`$ExecutablePath    # Полный путь к запущенному .exe файлу
)
#endregion

#region Логика обработки запуска
Write-Host "🚀 СПЕЦИАЛЬНЫЙ ОБРАБОТЧИК ЗАПУСКА для `$ProcessName" -ForegroundColor Green
Write-Host "   🆔 Process ID: `$ProcessId" -ForegroundColor Gray
Write-Host "   ⏰ Время запуска: `$(`$Timestamp.ToString('HH:mm:ss'))" -ForegroundColor Gray
Write-Host "   📁 Исполняемый файл: `$ExecutablePath" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════════════════════════════════════
# ПРИМЕРЫ СПЕЦИФИЧНЫХ ДЕЙСТВИЙ ПРИ ЗАПУСКЕ
# ═══════════════════════════════════════════════════════════════════════════════════════

#region 🔧 Настройка процесса
# Изменение приоритета процесса
try {
    `$process = Get-Process -Id `$ProcessId -ErrorAction Stop
    `$process.PriorityClass = "High"  # Normal, High, RealTime, etc.
    Write-Host "✅ Приоритет процесса установлен: High" -ForegroundColor Green
} catch {
    Write-Warning "⚠️ Не удалось изменить приоритет: `$_"
}

# Установка совместимости процесса (например, для старых программ)
# if (`$ProcessName -eq "oldapp") {
#     `$process.ProcessorAffinity = 1  # Использовать только первое ядро
#     Write-Host "🔧 Установлена совместимость для старого приложения" -ForegroundColor Cyan
# }
#endregion

#region 📁 Подготовка рабочего окружения
# Создание специфичных папок для процесса
`$workspaces = @(
    "C:\ProcessWorkspace\`$ProcessName",
    "C:\ProcessWorkspace\`$ProcessName\Temp",
    "C:\ProcessWorkspace\`$ProcessName\Logs",
    "C:\ProcessWorkspace\`$ProcessName\Data"
)

foreach (`$workspace in `$workspaces) {
    if (-not (Test-Path `$workspace)) {
        New-Item -ItemType Directory -Path `$workspace -Force | Out-Null
        Write-Host "📁 Создана папка: `$workspace" -ForegroundColor Cyan
    }
}

# Подготовка конфигурационных файлов
# `$configFile = "C:\ProcessWorkspace\`$ProcessName\config.ini"
# if (-not (Test-Path `$configFile)) {
#     @"
# [`$ProcessName Configuration]
# StartTime=`$(`$Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))
# ProcessId=`$ProcessId
# WorkspaceRoot=C:\ProcessWorkspace\`$ProcessName
# "@ | Out-File `$configFile -Encoding UTF8
#     Write-Host "⚙️ Создан конфигурационный файл" -ForegroundColor Blue
# }
#endregion

#region 🚀 Запуск сопутствующих сервисов
# Автоматический запуск связанных приложений
switch (`$ProcessName) {
    "notepad" {
        # Запуск калькулятора вместе с блокнотом
        if (-not (Get-Process "calc" -ErrorAction SilentlyContinue)) {
            Start-Process "calc" -WindowStyle Minimized
            Write-Host "🧮 Запущен калькулятор для работы с блокнотом" -ForegroundColor Blue
        }
    }
    
    "photoshop" {
        # Запуск Bridge для работы с Photoshop
        # Start-Process "C:\Program Files\Adobe\Adobe Bridge 2023\Bridge.exe" -WindowStyle Minimized
        # Write-Host "🌉 Запущен Adobe Bridge для работы с Photoshop" -ForegroundColor Magenta
    }
    
    "chrome" {
        # Запуск мониторинга производительности для браузера
        # Start-Process "perfmon" -ArgumentList "/s" -WindowStyle Minimized
        # Write-Host "📊 Запущен монитор производительности для Chrome" -ForegroundColor Yellow
    }
}
#endregion

#region 🛡️ Проверки безопасности и лицензий
# Проверка наличия лицензии
# `$licenseFile = "C:\Licenses\`$ProcessName.lic"
# if (-not (Test-Path `$licenseFile)) {
#     Write-Warning "⚠️ Файл лицензии не найден для `$ProcessName"
#     # Можно заблокировать запуск или отправить уведомление
# } else {
#     Write-Host "✅ Лицензия для `$ProcessName найдена" -ForegroundColor Green
# }

# Проверка наличия необходимых зависимостей
# `$requiredDLLs = @("vcruntime140.dll", "msvcp140.dll")
# foreach (`$dll in `$requiredDLLs) {
#     `$dllPath = Join-Path (Split-Path `$ExecutablePath -Parent) `$dll
#     if (-not (Test-Path `$dllPath)) {
#         Write-Warning "⚠️ Отсутствует зависимость: `$dll"
#     }
# }
#endregion

#region 📊 Телеметрия и мониторинг
# Отправка события запуска в систему мониторинга
`$startupEvent = @{
    EventType = "ProcessStarted"
    ProcessName = `$ProcessName
    ProcessId = `$ProcessId
    StartTime = `$Timestamp
    ExecutablePath = `$ExecutablePath
    UserName = `$env:USERNAME
    ComputerName = `$env:COMPUTERNAME
    SessionId = `$PID
}

# Логирование в JSON для последующего анализа
# `$logEntry = `$startupEvent | ConvertTo-Json -Compress
# Add-Content -Path "C:\Logs\process_starts.json" -Value `$logEntry

# Отправка в внешнюю систему мониторинга
# try {
#     Invoke-RestMethod -Uri "https://monitoring.company.com/events" -Method POST -Body (`$startupEvent | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 5
#     Write-Host "📡 Событие запуска отправлено в систему мониторинга" -ForegroundColor Green
# } catch {
#     Write-Warning "⚠️ Не удалось отправить событие в мониторинг: `$_"
# }
#endregion

#region 🔔 Уведомления
# Уведомление администратора о запуске критически важного процесса
# if (`$ProcessName -in @("sqlservr", "oracle", "postgres")) {
#     `$message = "Критически важный процесс `$ProcessName запущен на `$env:COMPUTERNAME в `$(`$Timestamp.ToString('HH:mm:ss'))"
#     
#     # Отправка email уведомления
#     # Send-MailMessage -To "admin@company.com" -Subject "Process Alert" -Body `$message -SmtpServer "smtp.company.com"
#     
#     # Запись в Event Log
#     # Write-EventLog -LogName Application -Source "ProcessMonitor" -EventId 1001 -EntryType Information -Message `$message
#     
#     Write-Host "📧 Отправлено уведомление администратору" -ForegroundColor Yellow
# }

# Показ toast-уведомления пользователю
# if (`$ProcessName -eq "backup") {
#     [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
#     # Здесь код для создания Toast уведомления
#     Write-Host "🔔 Показано уведомление пользователю о запуске резервного копирования" -ForegroundColor Cyan
# }
#endregion

#endregion

Write-Host "🎯 Специальная обработка запуска `$ProcessName завершена" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════════════
# РЕКОМЕНДАЦИИ ДЛЯ ОБРАБОТЧИКОВ ЗАПУСКА:
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# ✅ ПОДХОДИТ ДЛЯ:
# - Инициализация ресурсов и окружения
# - Настройка параметров процесса
# - Запуск сопутствующих сервисов
# - Проверка предварительных условий
# - Подготовка рабочих данных
#
# ❌ НЕ ПОДХОДИТ ДЛЯ:
# - Очистка ресурсов (используйте end.processName.ps1)
# - Архивирование данных (используйте end.processName.ps1)
# - Действий требующих завершения процесса
#
# 💡 СОВЕТЫ:
# 1. Обработчики запуска должны выполняться быстро
# 2. Избегайте блокирующих операций
# 3. Используйте асинхронные операции где возможно
# 4. Всегда проверяйте доступность ресурсов
# 5. Логируйте все важные действия для отладки
#
# ═══════════════════════════════════════════════════════════════════════════════════════
"@

    # Обработчик только завершения
    $templates["end.processName.ps1"] = @"
# ═══════════════════════════════════════════════════════════════════════════════════════
# ОБРАБОТЧИК ЗАВЕРШЕНИЯ ПРОЦЕССА
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# Файл: end.processName.ps1 (замените processName на реальное имя, например end.notepad.ps1)
#
# НАЗНАЧЕНИЕ:
# Этот скрипт вызывается ТОЛЬКО при завершении процесса
# Не вызывается при запуске процесса
#
# КОГДА ИСПОЛЬЗОВАТЬ:
# - Очистка временных файлов и ресурсов
# - Сохранение данных и конфигураций
# - Остановка сопутствующих сервисов
# - Архивирование логов и отчетов
# - Финализация рабочих процессов

#region Параметры скрипта
param(
    [string]`$ProcessName,      # Имя завершенного процесса без .exe
    [int]`$ProcessId,           # PID завершенного процесса (уже недоступен)
    [string]`$Action,           # Всегда будет "Stopped" для этого типа обработчика
    [datetime]`$Timestamp       # Точное время завершения процесса
    # Примечание: `$ExecutablePath недоступен при завершении процесса
)
#endregion

#region Логика обработки завершения
Write-Host "🏁 СПЕЦИАЛЬНЫЙ ОБРАБОТЧИК ЗАВЕРШЕНИЯ для `$ProcessName" -ForegroundColor Red
Write-Host "   🆔 Process ID был: `$ProcessId" -ForegroundColor Gray
Write-Host "   ⏰ Время завершения: `$(`$Timestamp.ToString('HH:mm:ss'))" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════════════════════════════════════
# ПРИМЕРЫ СПЕЦИФИЧНЫХ ДЕЙСТВИЙ ПРИ ЗАВЕРШЕНИИ
# ═══════════════════════════════════════════════════════════════════════════════════════

#region 🧹 Очистка временных файлов
Write-Host "🧹 Начинаем очистку временных файлов..." -ForegroundColor Yellow

# Очистка временных файлов процесса
`$tempLocations = @(
    "`$env:TEMP\`$ProcessName*",
    "`$env:LOCALAPPDATA\`$ProcessName\Temp\*",
    "C:\ProcessWorkspace\`$ProcessName\Temp\*"
)

`$cleanedFiles = 0
foreach (`$location in `$tempLocations) {
    try {
        `$files = Get-ChildItem `$location -ErrorAction SilentlyContinue
        if (`$files) {
            `$files | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            `$cleanedFiles += `$files.Count
        }
    } catch {
        Write-Warning "⚠️ Не удалось очистить `$location`: `$_"
    }
}

if (`$cleanedFiles -gt 0) {
    Write-Host "✅ Очищено временных файлов: `$cleanedFiles" -ForegroundColor Green
} else {
    Write-Host "ℹ️ Временные файлы не найдены" -ForegroundColor Blue
}

# Очистка кэша процесса
# `$cacheDir = "`$env:LOCALAPPDATA\`$ProcessName\Cache"
# if (Test-Path `$cacheDir) {
#     Remove-Item `$cacheDir -Recurse -Force -ErrorAction SilentlyContinue
#     Write-Host "🗂️ Кэш процесса очищен" -ForegroundColor Green
# }
#endregion

#region 💾 Сохранение и архивирование данных
Write-Host "💾 Сохранение данных сессии..." -ForegroundColor Cyan

# Архивирование логов процесса
`$logsToArchive = @(
    "C:\Logs\`$ProcessName.log",
    "C:\ProcessWorkspace\`$ProcessName\Logs\*.log"
)

foreach (`$logPattern in `$logsToArchive) {
    `$logFiles = Get-ChildItem `$logPattern -ErrorAction SilentlyContinue
    foreach (`$logFile in `$logFiles) {
        try {
            `$archivePath = "C:\Logs\Archive\`$ProcessName"
            if (-not (Test-Path `$archivePath)) {
                New-Item -ItemType Directory -Path `$archivePath -Force | Out-Null
            }
            
            `$newName = "`$(`$logFile.BaseName)_`$(Get-Date -Format 'yyyyMMdd_HHmmss')`$(`$logFile.Extension)"
            `$destinationPath = Join-Path `$archivePath `$newName
            
            Move-Item `$logFile.FullName `$destinationPath -Force
            Write-Host "📦 Лог архивирован: `$newName" -ForegroundColor Cyan
        } catch {
            Write-Warning "⚠️ Не удалось архивировать `$(`$logFile.Name): `$_"
        }
    }
}

# Сохранение статистики сессии
`$sessionStats = @{
    ProcessName = `$ProcessName
    ProcessId = `$ProcessId
    EndTime = `$Timestamp
    UserName = `$env:USERNAME
    ComputerName = `$env:COMPUTERNAME
    # Можно добавить больше метрик
}

# `$statsFile = "C:\Stats\sessions_`$(Get-Date -Format 'yyyyMM').json"
# `$sessionStats | ConvertTo-Json | Add-Content `$statsFile
# Write-Host "📊 Статистика сессии сохранена" -ForegroundColor Blue
#endregion

#region 🛑 Остановка связанных процессов и сервисов
Write-Host "🛑 Проверка связанных процессов..." -ForegroundColor Yellow

# Остановка процессов, запущенных вместе с основным
switch (`$ProcessName) {
    "notepad" {
        # Остановка калькулятора, если он был запущен для блокнота
        `$calcProcesses = Get-Process "calc" -ErrorAction SilentlyContinue
        if (`$calcProcesses) {
            `$calcProcesses | Stop-Process -Force
            Write-Host "🧮 Калькулятор остановлен вместе с блокнотом" -ForegroundColor Yellow
        }
    }
    
    "photoshop" {
        # Остановка Adobe Bridge если Photoshop завершился
        # Get-Process "*bridge*" -ErrorAction SilentlyContinue | Stop-Process -Force
        # Write-Host "🌉 Adobe Bridge остановлен вместе с Photoshop" -ForegroundColor Magenta
    }
    
    "chrome" {
        # Остановка мониторинга производительности
        # Get-Process "perfmon" -ErrorAction SilentlyContinue | Stop-Process -Force
        # Write-Host "📊 Монитор производительности остановлен" -ForegroundColor Yellow
    }
}

# Остановка сервисов, специфичных для процесса
# `$serviceName = "`$ProcessName`_Helper"
# `$service = Get-Service `$serviceName -ErrorAction SilentlyContinue
# if (`$service -and `$service.Status -eq "Running") {
#     Stop-Service `$serviceName -Force
#     Write-Host "🔧 Сервис `$serviceName остановлен" -ForegroundColor Yellow
# }
#endregion

#region 📊 Финальная отчетность и аналитика
# Расчет времени работы процесса (если известно время запуска)
# `$workingTimeFile = "C:\ProcessWorkspace\`$ProcessName\start_time.txt"
# if (Test-Path `$workingTimeFile) {
#     try {
#         `$startTime = [datetime](Get-Content `$workingTimeFile)
#         `$workingTime = `$Timestamp - `$startTime
#         
#         Write-Host "⏱️ Время работы процесса: `$([Math]::Round(`$workingTime.TotalMinutes, 1)) минут" -ForegroundColor Cyan
#         
#         # Удаляем файл времени запуска
#         Remove-Item `$workingTimeFile -Force
#         
#         # Сохраняем статистику времени работы
#         `$timeStats = @{
#             ProcessName = `$ProcessName
#             StartTime = `$startTime
#             EndTime = `$Timestamp  
#             Duration = `$workingTime.TotalMinutes
#         }
#         # `$timeStats | ConvertTo-Json | Add-Content "C:\Stats\working_times.json"
#         
#     } catch {
#         Write-Warning "⚠️ Не удалось рассчитать время работы: `$_"
#     }
# }

# Подсчет ресурсов, использованных процессом
# try {
#     `$processInfo = Get-WmiObject Win32_Process | Where-Object { `$_.ProcessId -eq `$ProcessId }
#     if (`$processInfo) {
#         Write-Host "💻 Пиковое использование памяти: `$([Math]::Round(`$processInfo.WorkingSetSize / 1MB, 1)) MB" -ForegroundColor Blue
#         Write-Host "🕐 Время CPU: `$([Math]::Round(`$processInfo.UserModeTime / 10000000, 2)) сек" -ForegroundColor Blue
#     }
# } catch {
#     # Процесс уже завершился, информация недоступна
# }
#endregion

#region 🔔 Уведомления о завершении
# Уведомление о завершении критически важных процессов
# if (`$ProcessName -in @("sqlservr", "oracle", "postgres")) {
#     `$message = "⚠️ ВНИМАНИЕ: Критически важный процесс `$ProcessName завершился на `$env:COMPUTERNAME в `$(`$Timestamp.ToString('HH:mm:ss'))"
#     
#     # Отправка срочного email
#     # Send-MailMessage -To "admin@company.com" -Subject "CRITICAL: Process Terminated" -Body `$message -Priority High -SmtpServer "smtp.company.com"
#     
#     # Запись в Event Log как предупреждение
#     # Write-EventLog -LogName Application -Source "ProcessMonitor" -EventId 2001 -EntryType Warning -Message `$message
#     
#     Write-Host "🚨 Отправлено критическое уведомление администратору" -ForegroundColor Red
# }

# Уведомление о завершении долгоработающих процессов
# if (`$workingTime -and `$workingTime.TotalHours -gt 4) {
#     Write-Host "📢 Процесс `$ProcessName работал более 4 часов" -ForegroundColor Yellow
#     # Здесь можно добавить специальную обработку для долгих сессий
# }
#endregion

#region 🔄 Подготовка к следующему запуску
# Подготовка чистого окружения для следующего запуска
# `$nextRunConfig = "C:\ProcessWorkspace\`$ProcessName\next_run.config"
# @"
# LastRun=`$(`$Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))
# LastPID=`$ProcessId
# LastUser=`$env:USERNAME
# CleanupCompleted=True
# "@ | Out-File `$nextRunConfig -Encoding UTF8
# Write-Host "⚙️ Конфигурация для следующего запуска подготовлена" -ForegroundColor Green

# Сброс счетчиков и состояний
# `$stateFile = "C:\ProcessWorkspace\`$ProcessName\state.txt"
# if (Test-Path `$stateFile) {
#     Remove-Item `$stateFile -Force
#     Write-Host "🔄 Состояние процесса сброшено" -ForegroundColor Blue
# }
#endregion

#endregion

Write-Host "✅ Завершающая обработка для `$ProcessName выполнена" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════════════
# РЕКОМЕНДАЦИИ ДЛЯ ОБРАБОТЧИКОВ ЗАВЕРШЕНИЯ:
# ═══════════════════════════════════════════════════════════════════════════════════════
#
# ✅ ПОДХОДИТ ДЛЯ:
# - Очистка временных файлов и ресурсов
# - Архивирование и сохранение данных
# - Остановка связанных процессов
# - Отправка финальных отчетов
# - Подготовка к следующему запуску
#
# ❌ НЕ ПОДХОДИТ ДЛЯ:
# - Инициализации ресурсов (используйте start.processName.ps1)
# - Настройки параметров запуска
# - Операций требующих работающий процесс
#
# ⚠️ ВАЖНО:
# 1. Процесс уже завершен - нельзя с ним взаимодействовать
# 2. `$ExecutablePath недоступен при завершении
# 3. Некоторая информация о процессе может быть недоступна
# 4. Обработчик должен быть устойчив к ошибкам
# 5. Избегайте долгих операций - они задерживают мониторинг
#
# 💡 СОВЕТЫ:
# 1. Всегда используйте try-catch для всех операций
# 2. Проверяйте существование файлов и папок
# 3. Логируйте все важные действия
# 4. Учитывайте что процесс мог завершиться аварийно
# 5. Делайте операции идемпотентными
#
# ═══════════════════════════════════════════════════════════════════════════════════════
"@

    return $templates
}

<#
.SYNOPSIS
Создает README файл с документацией.

.DESCRIPTION
Генерирует подробный README.md файл с описанием системы обработчиков.

.PARAMETER ExamplesPath
Путь к папке примеров.

.PARAMETER Force
Принудительно пересоздать файл.

.OUTPUTS
[PSCustomObject] - Информация о создании файла
#>
function Create-ReadmeFile {
    param(
        [string]$ExamplesPath,
        [switch]$Force
    )
    
    $readmePath = Join-Path $ExamplesPath "README.md"
    $result = [PSCustomObject]@{ Created = $false; Updated = $false }
    
    if ((Test-Path $readmePath) -and -not $Force) {
        return $result
    }
    
    $readmeContent = @"
# 📚 Process Monitor - Руководство по обработчикам

Добро пожаловать в систему автоматического мониторинга процессов! Эта папка содержит примеры обработчиков, которые показывают как создавать собственные скрипты для реагирования на события процессов.

## 🎯 Основные принципы

### Как это работает
1. **Поместите .ps1 файл** в папку `ProcessHandlers`
2. **Назовите файл по имени процесса** который хотите отслеживать
3. **Process Monitor автоматически** начнет мониторинг этого процесса
4. **При событии процесса** ваш скрипт автоматически выполнится

### Типы обработчиков

| Тип файла | Когда выполняется | Пример |
|-----------|------------------|---------|
| `processName.ps1` | При запуске И завершении | `notepad.ps1` |
| `start.processName.ps1` | Только при запуске | `start.notepad.ps1` |
| `end.processName.ps1` | Только при завершении | `end.notepad.ps1` |

## 📝 Параметры скриптов

Все обработчики получают следующие параметры:

\`\`\`powershell
param(
    [string]\$ProcessName,      # Имя процесса без .exe (например: "notepad")
    [int]\$ProcessId,           # Уникальный ID процесса (PID)
    [string]\$Action,           # "Started" или "Stopped"
    [datetime]\$Timestamp,      # Точное время события
    [string]\$ExecutablePath    # Полный путь к .exe (при запуске)
)
\`\`\`

> **Примечание:** `\$ExecutablePath` доступен только при запуске процесса, при завершении он пустой.

## 🚀 Быстрый старт

### Шаг 1: Скопируйте пример
Скопируйте один из файлов-примеров из этой папки в родительскую папку `ProcessHandlers`.

### Шаг 2: Переименуйте файл
Измените имя файла на имя процесса, который хотите отслеживать:
- `notepad.ps1` - для мониторинга блокнота
- `chrome.ps1` - для мониторинга браузера Chrome
- `start.photoshop.ps1` - только для запуска Photoshop

### Шаг 3: Настройте логику
Отредактируйте содержимое файла под ваши потребности.

### Шаг 4: Тестируйте
Запустите процесс и проверьте, что ваш обработчик выполняется.

## 🔧 Примеры использования

### Логирование активности
\`\`\`powershell
# В любом обработчике
"\$(Get-Date): \$Action - \$ProcessName (PID: \$ProcessId)" | Add-Content "process_log.txt"
\`\`\`

### Уведомления пользователя
\`\`\`powershell
if (\$Action -eq "Started") {
    [System.Windows.Forms.MessageBox]::Show("Запущен \$ProcessName!", "Process Monitor")
}
\`\`\`

### Автоматизация рабочего процесса
\`\`\`powershell
# При запуске Photoshop автоматически открыть Bridge
if (\$ProcessName -eq "photoshop" -and \$Action -eq "Started") {
    Start-Process "bridge.exe"
}
\`\`\`

### Очистка ресурсов
\`\`\`powershell
# При завершении процесса очистить временные файлы
if (\$Action -eq "Stopped") {
    Remove-Item "\$env:TEMP\\\$ProcessName*" -Force -Recurse -ErrorAction SilentlyContinue
}
\`\`\`

## 🛡️ Лучшие практики

### ✅ Рекомендуется
- **Используйте try-catch** для всех внешних операций
- **Проверяйте существование файлов** перед операциями с ними
- **Логируйте важные действия** для отладки
- **Делайте обработчики быстрыми** - избегайте долгих операций
- **Тестируйте обработчики** перед использованием в продакшене

### ❌ Избегайте
- **Блокирующих операций** - они замедляют мониторинг
- **Операций требующих пользовательского ввода**
- **Изменения критически важных системных настроек**
- **Запуска ресурсоемких процессов** без необходимости

## 🔍 Отладка

### Просмотр логов Process Monitor
Process Monitor выводит информацию в консоль. Для просмотра логов:
1. Запустите Process Monitor из командной строки
2. Наблюдайте за сообщениями при запуске/завершении процессов

### Отладка собственных скриптов
- Используйте `Write-Host` для вывода отладочной информации
- Добавляйте логирование в файлы для анализа
- Проверяйте Event Viewer Windows на наличие ошибок

### Тестирование обработчиков
\`\`\`powershell
# Ручной вызов обработчика для тестирования
.\notepad.ps1 -ProcessName "notepad" -ProcessId 1234 -Action "Started" -Timestamp (Get-Date) -ExecutablePath "C:\Windows\notepad.exe"
\`\`\`

## 📋 Список примеров в этой папке

| Файл | Описание |
|------|----------|
| `processName.ps1` | Универсальный обработчик с примерами для обоих событий |
| `start.processName.ps1` | Специализированный обработчик запуска |
| `end.processName.ps1` | Специализированный обработчик завершения |
| `README.md` | Этот файл с документацией |

## 🆘 Получение помощи

### Проблемы с обработчиками
1. **Проверьте имя файла** - оно должно точно соответствовать имени процесса
2. **Проверьте синтаксис PowerShell** - используйте PowerShell ISE для проверки
3. **Проверьте права выполнения** - возможно нужен запуск от администратора
4. **Посмотрите логи** - Process Monitor выводит ошибки в консоль

### Часто задаваемые вопросы

**Q: Почему мой обработчик не вызывается?**
A: Проверьте имя файла и убедитесь что процесс действительно запускается с таким именем.

**Q: Можно ли обрабатывать несколько процессов одним скриптом?**
A: Нет, один файл = один процесс. Но можно создать общую библиотеку функций.

**Q: Что делать если процесс имеет пробелы в имени?**
A: Используйте имя без пробелов или замените пробелы на подчеркивания.

**Q: Как обрабатывать процессы с одинаковыми именами но разными путями?**
A: Используйте параметр `\$ExecutablePath` для различения процессов.

## 🔗 Дополнительные ресурсы

- [Документация PowerShell](https://docs.microsoft.com/powershell/)
- [Примеры автоматизации Windows](https://github.com/PowerShell/PowerShell)
- [Best Practices для PowerShell скриптов](https://docs.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)

---

**Удачи в автоматизации! 🚀**

> Process Monitor создан для упрощения мониторинга и автоматизации процессов. 
> Если у вас есть предложения по улучшению - создавайте собственные обработчики и делитесь опытом!
"@

    try {
        $readmeContent | Out-File -FilePath $readmePath -Encoding UTF8 -Force
        
        if ($Force -and (Test-Path $readmePath)) {
            $result.Updated = $true
        }
        else {
            $result.Created = $true
        }
        
        Write-LogMessage "📚 README файл создан" -Color Green
    }
    catch {
        Write-LogMessage "❌ Ошибка создания README: $_" -Color Red
    }
    
    return $result
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                      КОНЕЦ СЕКЦИИ ГЕНЕРАЦИИ ПРИМЕРОВ                           
#endregion ═══════════════════════════════════════════════════════════════════════════════

# Подгружаем ServiceFunctions если доступен (только если Write-LogMessage недоступна)
if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $PSScriptRoot "ServiceFunctions.ps1")) {
        . (Join-Path $PSScriptRoot "ServiceFunctions.ps1")
    }
    else {
        # Простая альтернативная функция логирования если ServiceFunctions недоступен
        function Write-LogMessage {
            param([string]$Message, [ConsoleColor]$Color = "White")
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
        }
    }
}

Write-LogMessage "✅ ExamplesGenerator.ps1 загружен успешно" -Color Green -NoTimestamp