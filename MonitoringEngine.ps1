# MonitoringEngine.ps1 - Process Monitor Core Engine
# Основная логика мониторинга процессов на основе файлов обработчиков
#
# Возможности:
# - Автоматическое сканирование обработчиков в папке ProcessHandlers
# - WMI события + polling fallback для совместимости
# - Hot-reload при изменении файлов обработчиков
# - Выполнение пользовательских скриптов с параметрами
# - Бесконечная работа даже при отсутствии обработчиков
#
# Использование:
# . "MonitoringEngine.ps1"
# Start-ProcessMonitoring -HandlersPath "ProcessHandlers"

#region ═══════════════════════════════════════════════════════════════════════════════════
#region                        📁 СКАНИРОВАНИЕ ОБРАБОТЧИКОВ                               
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Сканирует папку ProcessHandlers и возвращает найденные обработчики.

.DESCRIPTION
Анализирует .ps1 файлы в папке и классифицирует их по типам:
- processName.ps1 - универсальные обработчики
- start.processName.ps1 - обработчики запуска
- end.processName.ps1 - обработчики завершения

.PARAMETER HandlersPath
Путь к папке с обработчиками.

.EXAMPLE
$handlers = Get-ProcessHandlers -HandlersPath "ProcessHandlers"

.OUTPUTS
[hashtable] - Словарь с классифицированными обработчиками
#>
function Get-ProcessHandlers {
    param(
        [string]$HandlersPath
    )
    
    $handlers = @{
        Universal = @{}    # processName.ps1
        Start     = @{}        # start.processName.ps1  
        End       = @{}          # end.processName.ps1
        Files     = @()        # Все найденные файлы для мониторинга
    }
    
    if (-not (Test-Path $HandlersPath)) {
        Write-LogMessage "⚠️ Папка обработчиков не найдена: $HandlersPath" -Color Yellow
        return $handlers
    }
    
    try {

        # Получаем все .ps1 файлы, исключая папку _examples
        $scriptFiles = Get-ChildItem -Path $HandlersPath -Filter "*.ps1" -File | Where-Object { 
            $_.Directory.Name -ne "_examples" -and
            $_.DirectoryName -eq (Resolve-Path $HandlersPath).Path
        }
        
        $handlers.Files = $scriptFiles.FullName
        
        foreach ($file in $scriptFiles) {
            $name = $file.BaseName
            
            if ($name -match '^start\.(.+)$') {
                # start.processName.ps1
                $processName = $matches[1]
                $handlers.Start[$processName] = $file.FullName
                Write-LogMessage "🟢 Найден обработчик запуска: $processName" -Color Green
            }
            elseif ($name -match '^end\.(.+)$') {
                # end.processName.ps1  
                $processName = $matches[1]
                $handlers.End[$processName] = $file.FullName
                Write-LogMessage "🔴 Найден обработчик завершения: $processName" -Color Red
            }
            elseif ($name -notmatch '^(start|end)\.') {
                # processName.ps1 (универсальный)
                $handlers.Universal[$name] = $file.FullName
                Write-LogMessage "🔵 Найден универсальный обработчик: $name" -Color Blue
            }
        }
        
        $totalHandlers = $handlers.Universal.Count + $handlers.Start.Count + $handlers.End.Count
        Write-LogMessage "📊 Всего обработчиков найдено: $totalHandlers" -Color Cyan
        
        return $handlers
    }
    catch {
        Write-LogMessage "❌ Ошибка сканирования обработчиков: $_" -Color Red
        return $handlers
    }
}

<#
.SYNOPSIS
Получает список процессов для мониторинга на основе найденных обработчиков.

.DESCRIPTION
Анализирует обработчики и возвращает уникальный список имен процессов для отслеживания.

.PARAMETER Handlers
Словарь обработчиков, полученный от Get-ProcessHandlers.

.OUTPUTS
[array] - Массив имен процессов для мониторинга
#>
function Get-MonitoredProcesses {
    param($Handlers)
    
    $processes = @()
    $processes += $Handlers.Universal.Keys
    $processes += $Handlers.Start.Keys  
    $processes += $Handlers.End.Keys
    
    return ($processes | Sort-Object -Unique)
}

<#
.SYNOPSIS
Отображает информацию о найденных обработчиках.

.DESCRIPTION
Выводит красивую сводку по типам обработчиков для каждого процесса.

.PARAMETER Handlers
Словарь обработчиков.

.PARAMETER MonitoredProcesses
Список отслеживаемых процессов.
#>
function Show-HandlersInfo {
    param($Handlers, $MonitoredProcesses)
    
    Write-Host ""
    Write-LogMessage "📋 Обзор найденных обработчиков:" -Color Cyan
    
    if ($MonitoredProcesses.Count -eq 0) {
        Write-LogMessage "   ❌ Обработчики не найдены" -Color Red
        return
    }
    
    foreach ($process in $MonitoredProcesses) {
        $handlerTypes = @()
        
        if ($Handlers.Universal.ContainsKey($process)) { 
            $handlerTypes += "Universal" 
        }
        if ($Handlers.Start.ContainsKey($process)) { 
            $handlerTypes += "Start" 
        }
        if ($Handlers.End.ContainsKey($process)) { 
            $handlerTypes += "End" 
        }
        
        $typeStr = $handlerTypes -join ", "
        Write-LogMessage "   • $process [$typeStr]" -Color White
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                    КОНЕЦ СЕКЦИИ СКАНИРОВАНИЯ ОБРАБОТЧИКОВ                      
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                       🔄 HOT-RELOAD ОБРАБОТЧИКОВ                                  
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Запускает мониторинг изменений в папке обработчиков.

.DESCRIPTION
Использует FileSystemWatcher для отслеживания добавления/удаления файлов обработчиков
и автоматического обновления списка отслеживаемых процессов.

.PARAMETER HandlersPath
Путь к папке с обработчиками.

.OUTPUTS
[bool] - True если мониторинг запущен успешно
#>
function Start-HandlersWatcher {
    param([string]$HandlersPath)
    
    try {
        if (-not (Test-Path $HandlersPath)) {
            Write-LogMessage "⚠️ Папка для мониторинга не существует: $HandlersPath" -Color Yellow
            return $false
        }
        
        $global:HandlersWatcher = New-Object System.IO.FileSystemWatcher
        $global:HandlersWatcher.Path = (Resolve-Path $HandlersPath).Path
        $global:HandlersWatcher.Filter = "*.ps1"
        $global:HandlersWatcher.IncludeSubdirectories = $false
        $global:HandlersWatcher.EnableRaisingEvents = $true
        
        # Обработчик создания файлов
        Register-ObjectEvent -InputObject $global:HandlersWatcher -EventName "Created" -Action {
            $filePath = $Event.SourceEventArgs.FullPath
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
            
            # Игнорируем файлы в папке _examples
            if ($filePath -notlike "*_examples*") {
                Start-Sleep -Milliseconds 100  # Даем файлу время записаться
                Write-LogMessage "➕ Добавлен обработчик: $fileName" -Color Green
                Update-MonitoredProcesses
            }
        } | Out-Null
        
        # Обработчик удаления файлов
        Register-ObjectEvent -InputObject $global:HandlersWatcher -EventName "Deleted" -Action {
            $filePath = $Event.SourceEventArgs.FullPath
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
            
            if ($filePath -notlike "*_examples*") {
                Write-LogMessage "➖ Удален обработчик: $fileName" -Color Red
                Update-MonitoredProcesses
            }
        } | Out-Null
        
        # Обработчик переименования файлов
        Register-ObjectEvent -InputObject $global:HandlersWatcher -EventName "Renamed" -Action {
            $oldPath = $Event.SourceEventArgs.OldFullPath
            $newPath = $Event.SourceEventArgs.FullPath
            $oldName = [System.IO.Path]::GetFileNameWithoutExtension($oldPath)
            $newName = [System.IO.Path]::GetFileNameWithoutExtension($newPath)
            
            # Игнорируем файлы в папке _examples
            if ($oldPath -notlike "*_examples*" -and $newPath -notlike "*_examples*") {
                Start-Sleep -Milliseconds 100  # Даем файлу время записаться
                Write-LogMessage "🔄 Переименован обработчик: $oldName → $newName" -Color Cyan
                Update-MonitoredProcesses
            }
        } | Out-Null
        
        Write-LogMessage "👁️ Мониторинг файлов обработчиков включен" -Color Green
        return $true
    }
    catch {
        Write-LogMessage "❌ Ошибка запуска мониторинга файлов: $_" -Color Red
        return $false
    }
}

<#
.SYNOPSIS
Останавливает мониторинг изменений файлов обработчиков.

.DESCRIPTION
Корректно останавливает FileSystemWatcher и очищает ресурсы.
#>
function Stop-HandlersWatcher {
    if ($global:HandlersWatcher) {
        try {
            $global:HandlersWatcher.EnableRaisingEvents = $false
            $global:HandlersWatcher.Dispose()
            Remove-Variable -Name "HandlersWatcher" -Scope Global -ErrorAction SilentlyContinue
            
            # Удаляем обработчики событий FileSystemWatcher
            Get-EventSubscriber | Where-Object { 
                $_.SourceObject -and $_.SourceObject.GetType().Name -eq "FileSystemWatcher" 
            } | Unregister-Event -Force
            
            Write-LogMessage "👁️ Мониторинг файлов обработчиков остановлен" -Color Yellow
        }
        catch {
            Write-LogMessage "⚠️ Ошибка остановки мониторинга файлов: $_" -Color Yellow
        }
    }
}

<#
.SYNOPSIS
Обновляет список отслеживаемых процессов при изменении обработчиков.

.DESCRIPTION
Пересканирует обработчики и обновляет WMI события или polling список.
Вызывается автоматически при изменении файлов.
#>
function Update-MonitoredProcesses {
    try {
        Write-LogMessage "🔄 Обновление списка отслеживаемых процессов..." -Color Cyan
        
        # Пересканируем обработчики
        $global:ProcessHandlers = Get-ProcessHandlers -HandlersPath $global:MonitoringConfig.HandlersPath
        $newProcesses = Get-MonitoredProcesses -Handlers $global:ProcessHandlers
        $oldProcesses = $global:MonitoringConfig.MonitoredProcesses
        
        # Определяем изменения
        $added = $newProcesses | Where-Object { $_ -notin $oldProcesses }
        $removed = $oldProcesses | Where-Object { $_ -notin $newProcesses }
        
        if ($added -or $removed) {
            if ($added) {
                Write-LogMessage "✅ Добавлены процессы: $($added -join ', ')" -Color Green
                
                # Проверяем уже запущенные процессы для новых обработчиков
                foreach ($processName in $added) {
                    $runningProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
                    foreach ($proc in $runningProcesses) {
                        Write-LogMessage "🔵 Найден работающий процесс: $processName (PID: $($proc.Id))" -Color Blue
                        Handle-ProcessEvent -ProcessName $processName -ProcessId $proc.Id -Action "Started" -ExecutablePath $proc.Path
                    }
                }
            }
            
            if ($removed) {
                Write-LogMessage "🗑️ Удалены процессы: $($removed -join ', ')" -Color Red
            }
            
            # Обновляем глобальную конфигурацию
            $global:MonitoringConfig.MonitoredProcesses = $newProcesses
            
            # Перерегистрируем WMI события если используются
            if ($global:MonitoringConfig.UseWMIEvents) {
                Update-WMIEventRegistration -ProcessNames $newProcesses
            }
        }
        else {
            Write-LogMessage "ℹ️ Список процессов не изменился" -Color Blue
        }
    }
    catch {
        Write-LogMessage "❌ Ошибка обновления процессов: $_" -Color Red
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                    КОНЕЦ СЕКЦИИ HOT-RELOAD ОБРАБОТЧИКОВ                        
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                      ⚙️ ВЫПОЛНЕНИЕ ОБРАБОТЧИКОВ                                    
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Выполняет пользовательский обработчик процесса.

.DESCRIPTION
Запускает .ps1 файл обработчика с необходимыми параметрами.

.PARAMETER ScriptPath
Путь к файлу обработчика.

.PARAMETER ProcessName
Имя процесса.

.PARAMETER ProcessId
ID процесса.

.PARAMETER Action
Действие: "Started" или "Stopped".

.PARAMETER ExecutablePath
Путь к исполняемому файлу (опционально).

.OUTPUTS
[bool] - True если выполнено успешно
#>
function Invoke-ProcessHandler {
    param(
        [string]$ScriptPath,
        [string]$ProcessName,
        [int]$ProcessId,
        [string]$Action,
        [string]$ExecutablePath = ""
    )
    
    try {
        if (-not (Test-Path $ScriptPath)) {
            Write-LogMessage "⚠️ Обработчик не найден: $ScriptPath" -Color Yellow
            return $false
        }
        
        $timestamp = Get-Date
        $scriptName = Split-Path $ScriptPath -Leaf
        
        Write-LogMessage "🔧 Запуск: $scriptName" -Color Cyan
        
        # Формируем аргументы для PowerShell
        $arguments = @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$ScriptPath`""
            "-ProcessName", "`"$ProcessName`""
            "-ProcessId", $ProcessId
            "-Action", "`"$Action`""
            "-Timestamp", "`"$timestamp`""
        )
        
        if ($ExecutablePath) {
            $arguments += "-ExecutablePath", "`"$ExecutablePath`""
        }
        
        # ПРОСТО ЗАПУСКАЕМ И ЗАБЫВАЕМ
        Start-Process -FilePath "PowerShell.exe" -ArgumentList $arguments 
        # -WindowStyle Hidden
        
        Write-LogMessage "🚀 Обработчик $scriptName запущен" -Color Green
        return $true
    }
    catch {
        Write-LogMessage "❌ Ошибка запуска обработчика $ScriptPath`: $_" -Color Red
        return $false
    }
}

<#
.SYNOPSIS
Обрабатывает событие процесса, вызывая соответствующие обработчики.

.DESCRIPTION
Определяет какие обработчики нужно вызвать для данного события и выполняет их.

.PARAMETER ProcessName
Имя процесса.

.PARAMETER ProcessId
ID процесса.

.PARAMETER Action
Действие: "Started" или "Stopped".

.PARAMETER ExecutablePath
Путь к исполняемому файлу (опционально).
#>
function Handle-ProcessEvent {
    param(
        [string]$ProcessName,
        [int]$ProcessId,
        [string]$Action,
        [string]$ExecutablePath = ""
    )
    
    $timestamp = Get-Date
    $actionIcon = if ($Action -eq "Started") { "🟢" } else { "🔴" }
    
    Write-LogMessage "$actionIcon [$($timestamp.ToString('HH:mm:ss'))] $ProcessName $Action (PID: $ProcessId)" -Color $(if ($Action -eq "Started") { "Green" } else { "Red" })
    
    $handlersExecuted = 0
    
    # 1. Универсальный обработчик (выполняется всегда если есть)
    if ($global:ProcessHandlers.Universal.ContainsKey($ProcessName)) {
        $universalHandler = $global:ProcessHandlers.Universal[$ProcessName]
        if (Invoke-ProcessHandler -ScriptPath $universalHandler -ProcessName $ProcessName -ProcessId $ProcessId -Action $Action -ExecutablePath $ExecutablePath) {
            $handlersExecuted++
        }
    }
    
    # 2. Специфичный обработчик в зависимости от действия
    $specificHandler = $null
    switch ($Action) {
        "Started" { 
            if ($global:ProcessHandlers.Start.ContainsKey($ProcessName)) {
                $specificHandler = $global:ProcessHandlers.Start[$ProcessName]
            }
        }
        "Stopped" { 
            if ($global:ProcessHandlers.End.ContainsKey($ProcessName)) {
                $specificHandler = $global:ProcessHandlers.End[$ProcessName]
            }
        }
    }
    
    if ($specificHandler) {
        if (Invoke-ProcessHandler -ScriptPath $specificHandler -ProcessName $ProcessName -ProcessId $ProcessId -Action $Action -ExecutablePath $ExecutablePath) {
            $handlersExecuted++
        }
    }
    
    if ($handlersExecuted -eq 0) {
        Write-LogMessage "⚠️ Обработчики для $ProcessName не найдены или не выполнены" -Color Yellow
    }
    else {
        Write-LogMessage "🎯 Выполнено обработчиков: $handlersExecuted" -Color Blue
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                   КОНЕЦ СЕКЦИИ ВЫПОЛНЕНИЯ ОБРАБОТЧИКОВ                         
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                          🎯 WMI СОБЫТИЯ                                            
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Регистрирует WMI события для мониторинга процессов.

.DESCRIPTION
Создает подписки на Win32_ProcessStartTrace и Win32_ProcessStopTrace для отслеживания процессов.

.PARAMETER ProcessNames
Массив имен процессов для мониторинга.

.OUTPUTS
[bool] - True если события зарегистрированы успешно
#>
function Register-ProcessWMIEvents {
    param([array]$ProcessNames)
    
    if ($ProcessNames.Count -eq 0) {
        Write-LogMessage "⚠️ Нет процессов для регистрации WMI событий" -Color Yellow
        return $false
    }
    
    try {
        # Проверяем доступность WMI
        $null = Get-WmiObject -Class Win32_Process -List -ErrorAction Stop
        
        # Создаем фильтр для мониторируемых процессов
        $processFilter = ($ProcessNames | ForEach-Object { "ProcessName='$_.exe'" }) -join " OR "
        
        Write-LogMessage "🔍 Регистрация WMI событий для процессов: $($ProcessNames -join ', ')" -Color Cyan
        
        # Событие запуска процессов
        $startQuery = "SELECT * FROM Win32_ProcessStartTrace WHERE $processFilter"
        Register-WmiEvent -Query $startQuery -Action {
            $processName = $Event.SourceEventArgs.NewEvent.ProcessName -replace '\.exe$', ''
            $processId = $Event.SourceEventArgs.NewEvent.ProcessID
            
            # Получаем путь к исполняемому файлу
            $executablePath = ""
            try {
                $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($proc) {
                    $executablePath = $proc.Path
                }
            }
            catch { }
            
            Handle-ProcessEvent -ProcessName $processName -ProcessId $processId -Action "Started" -ExecutablePath $executablePath
        } -ErrorAction Stop | Out-Null
        
        # Событие завершения процессов
        $stopQuery = "SELECT * FROM Win32_ProcessStopTrace WHERE $processFilter"  
        Register-WmiEvent -Query $stopQuery -Action {
            $processName = $Event.SourceEventArgs.NewEvent.ProcessName -replace '\.exe$', ''
            $processId = $Event.SourceEventArgs.NewEvent.ProcessID
            
            Handle-ProcessEvent -ProcessName $processName -ProcessId $processId -Action "Stopped"
        } -ErrorAction Stop | Out-Null
        
        Write-LogMessage "✅ WMI события зарегистрированы для $($ProcessNames.Count) процессов" -Color Green
        return $true
    }
    catch {
        Write-LogMessage "❌ Ошибка регистрации WMI событий: $_" -Color Red
        Write-LogMessage "🔄 Переключение на polling режим..." -Color Yellow
        return $false
    }
}

<#
.SYNOPSIS
Обновляет регистрацию WMI событий при изменении списка процессов.

.DESCRIPTION
Удаляет старые подписки и создает новые для обновленного списка процессов.

.PARAMETER ProcessNames
Новый список имен процессов.
#>
function Update-WMIEventRegistration {
    param([array]$ProcessNames)
    
    try {
        Write-LogMessage "🔄 Обновление WMI событий..." -Color Cyan
        
        # Удаляем старые WMI подписки
        $wmiSubscribers = Get-EventSubscriber | Where-Object { 
            $_.SourceObject -and $_.SourceObject.GetType().Name -eq "ManagementEventWatcher" 
        }
        
        if ($wmiSubscribers) {
            $wmiSubscribers | Unregister-Event -Force
            Write-LogMessage "🗑️ Старые WMI события удалены" -Color Yellow
        }
        
        # Регистрируем новые события
        if ($ProcessNames.Count -gt 0) {
            $success = Register-ProcessWMIEvents -ProcessNames $ProcessNames
            if (-not $success) {
                Write-LogMessage "⚠️ Не удалось перерегистрировать WMI события" -Color Yellow
                $global:MonitoringConfig.UseWMIEvents = $false
            }
        }
    }
    catch {
        Write-LogMessage "❌ Ошибка обновления WMI событий: $_" -Color Red
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                        КОНЕЦ СЕКЦИИ WMI СОБЫТИЙ                                
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                          📊 POLLING РЕЖИМ                                          
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Запускает polling режим мониторинга процессов.

.DESCRIPTION
Альтернативный режим мониторинга через периодическую проверку списка процессов.
Используется когда WMI события недоступны.

.PARAMETER IntervalSeconds
Интервал проверки в секундах. По умолчанию 2 секунды.
#>
function Start-PollingMode {
    param([int]$IntervalSeconds = 2)
    
    Write-LogMessage "🔄 Запуск polling режима (интервал: $IntervalSeconds сек)" -Color Yellow
    
    # Инициализируем отслеживание процессов
    $global:TrackedProcesses = @{}
    
    while ($true) {
        try {
            $currentProcessList = $global:MonitoringConfig.MonitoredProcesses
            
            if ($currentProcessList.Count -eq 0) {
                Start-Sleep -Seconds $IntervalSeconds
                continue
            }
            
            foreach ($processName in $currentProcessList) {
                # Получаем текущие процессы
                $currentProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
                $currentPIDs = @($currentProcesses | ForEach-Object { $_.Id })
                
                # Проверяем новые процессы
                foreach ($proc in $currentProcesses) {
                    if (-not $global:TrackedProcesses.ContainsKey($proc.Id)) {
                        $global:TrackedProcesses[$proc.Id] = @{
                            Name      = $processName
                            StartTime = Get-Date
                        }
                        Handle-ProcessEvent -ProcessName $processName -ProcessId $proc.Id -Action "Started" -ExecutablePath $proc.Path
                    }
                }
                
                # Проверяем завершившиеся процессы
                $trackedPIDsForProcess = @($global:TrackedProcesses.GetEnumerator() | 
                    Where-Object { $_.Value.Name -eq $processName } | 
                    ForEach-Object { $_.Key })
                
                foreach ($pid in $trackedPIDsForProcess) {
                    if ($pid -notin $currentPIDs) {
                        Handle-ProcessEvent -ProcessName $processName -ProcessId $pid -Action "Stopped"
                        $global:TrackedProcesses.Remove($pid)
                    }
                }
            }
            
            Start-Sleep -Seconds $IntervalSeconds
            
        }
        catch [System.Management.Automation.PipelineStoppedException] {
            Write-LogMessage "🛑 Polling режим остановлен" -Color Yellow
            break
        }
        catch {
            Write-LogMessage "❌ Ошибка в polling режиме: $_" -Color Red
            Start-Sleep -Seconds ($IntervalSeconds * 2)  # Увеличиваем интервал при ошибке
        }
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                       КОНЕЦ СЕКЦИИ POLLING РЕЖИМА                              
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                      🚀 ОСНОВНАЯ ЛОГИКА МОНИТОРИНГА                               
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Инициализирует глобальную конфигурацию мониторинга.

.DESCRIPTION
Создает глобальный объект конфигурации с настройками мониторинга.

.PARAMETER HandlersPath
Путь к папке с обработчиками.
#>
function Initialize-MonitoringConfig {
    param([string]$HandlersPath)
    
    $global:MonitoringConfig = [PSCustomObject]@{
        HandlersPath       = $HandlersPath
        MonitoredProcesses = @()
        UseWMIEvents       = $false
        StartTime          = Get-Date
        IsRunning          = $false
    }
    
    $global:ProcessHandlers = @{
        Universal = @{}
        Start     = @{}  
        End       = @{}
        Files     = @()
    }
    
    $global:TrackedProcesses = @{}
}

<#
.SYNOPSIS
Запускает мониторинг процессов.

.DESCRIPTION
Основная функция для запуска системы мониторинга процессов.
Инициализирует все компоненты и запускает основной цикл.

.PARAMETER HandlersPath
Путь к папке с обработчиками процессов.

.EXAMPLE
Start-ProcessMonitoring -HandlersPath "ProcessHandlers"

.OUTPUTS
[bool] - True если мониторинг запущен успешно
#>
function Start-ProcessMonitoring {
    param(
        [string]$HandlersPath = "ProcessHandlers"
    )
    
    Write-LogMessage "🚀 Запуск системы мониторинга процессов..." -Color Cyan
    Write-LogMessage "📁 Папка обработчиков: $HandlersPath" -Color Blue
    
    # Инициализируем конфигурацию
    Initialize-MonitoringConfig -HandlersPath $HandlersPath
    
    # Убеждаемся что папка существует
    if (-not (Test-Path $HandlersPath)) {
        Write-LogMessage "📁 Создание папки обработчиков..." -Color Yellow
        try {
            New-Item -ItemType Directory -Path $HandlersPath -Force | Out-Null
            Write-LogMessage "✅ Папка создана: $HandlersPath" -Color Green
        }
        catch {
            Write-LogMessage "❌ Не удалось создать папку: $_" -Color Red
            return $false
        }
    }
    
    # Запускаем мониторинг файлов обработчиков
    $watcherStarted = Start-HandlersWatcher -HandlersPath $HandlersPath
    if (-not $watcherStarted) {
        Write-LogMessage "⚠️ Мониторинг файлов недоступен, изменения не будут отслеживаться" -Color Yellow
    }
    
    # Основной цикл мониторинга
    $global:MonitoringConfig.IsRunning = $true
    
    try {
        while ($global:MonitoringConfig.IsRunning) {
            # Сканируем обработчики
            Write-LogMessage "🔍 Сканирование обработчиков..." -Color Cyan
            $global:ProcessHandlers = Get-ProcessHandlers -HandlersPath $HandlersPath
            $monitoredProcesses = Get-MonitoredProcesses -Handlers $global:ProcessHandlers
            $global:MonitoringConfig.MonitoredProcesses = $monitoredProcesses
            
            # Показываем информацию о найденных обработчиках
            Show-HandlersInfo -Handlers $global:ProcessHandlers -MonitoredProcesses $monitoredProcesses
            
            if ($monitoredProcesses.Count -eq 0) {
                Write-LogMessage "😴 Обработчики не найдены. Ожидание файлов..." -Color Yellow
                Write-LogMessage "💡 Создайте .ps1 файлы в папке $HandlersPath" -Color Cyan
                
                # Ожидаем появления обработчиков
                do {
                    Start-Sleep -Seconds 5
                    $tempHandlers = Get-ProcessHandlers -HandlersPath $HandlersPath
                    $tempProcesses = Get-MonitoredProcesses -Handlers $tempHandlers
                } while ($tempProcesses.Count -eq 0 -and $global:MonitoringConfig.IsRunning)
                
                if (-not $global:MonitoringConfig.IsRunning) {
                    break
                }
                
                Write-LogMessage "🎉 Обработчики обнаружены! Запуск мониторинга..." -Color Green
                continue
            }
            
            # Пробуем WMI события
            Write-LogMessage "🔧 Попытка регистрации WMI событий..." -Color Cyan
            $wmiSuccess = Register-ProcessWMIEvents -ProcessNames $monitoredProcesses
            $global:MonitoringConfig.UseWMIEvents = $wmiSuccess
            
            if ($wmiSuccess) {
                Write-LogMessage "✅ Режим: WMI события (оптимальный)" -Color Green
                
                # Проверяем уже запущенные процессы
                Write-LogMessage "🔎 Проверка уже запущенных процессов..." -Color Blue
                foreach ($processName in $monitoredProcesses) {
                    $runningProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
                    foreach ($proc in $runningProcesses) {
                        Write-LogMessage "🔵 Найден работающий: $processName (PID: $($proc.Id))" -Color Blue
                        Handle-ProcessEvent -ProcessName $processName -ProcessId $proc.Id -Action "Started" -ExecutablePath $proc.Path
                    }
                }
                
                Write-LogMessage "👂 Мониторинг активен. Ожидание событий процессов..." -Color Green
                Write-LogMessage "🔄 Нажмите Ctrl+C для остановки" -Color Cyan
                
                # Цикл ожидания WMI событий
                try {
                    while ($global:MonitoringConfig.IsRunning) {
                        Start-Sleep -Seconds 1
                    }
                }
                catch [System.Management.Automation.PipelineStoppedException] {
                    Write-LogMessage "🛑 Получен сигнал остановки" -Color Yellow
                    break
                }
            }
            else {
                Write-LogMessage "🔄 Режим: Polling (совместимый)" -Color Yellow
                
                # Проверяем уже запущенные процессы для polling режима
                Write-LogMessage "🔎 Инициализация tracking для polling режима..." -Color Blue
                foreach ($processName in $monitoredProcesses) {
                    $runningProcesses = Get-Process -Name $processName -ErrorAction SilentlyContinue
                    foreach ($proc in $runningProcesses) {
                        $global:TrackedProcesses[$proc.Id] = @{
                            Name      = $processName
                            StartTime = Get-Date
                        }
                        Write-LogMessage "🔵 Добавлен в tracking: $processName (PID: $($proc.Id))" -Color Blue
                        Handle-ProcessEvent -ProcessName $processName -ProcessId $proc.Id -Action "Started" -ExecutablePath $proc.Path
                    }
                }
                
                Write-LogMessage "👂 Polling мониторинг активен..." -Color Green
                Write-LogMessage "🔄 Нажмите Ctrl+C для остановки" -Color Cyan
                
                # Запускаем polling режим
                Start-PollingMode -IntervalSeconds 2
                break
            }
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-LogMessage "🛑 Получен сигнал остановки (Ctrl+C)" -Color Yellow
    }
    catch {
        Write-LogMessage "❌ Критическая ошибка мониторинга: $_" -Color Red
    }
    finally {
        Stop-ProcessMonitoring
    }
    
    return $true
}

<#
.SYNOPSIS
Останавливает мониторинг процессов.

.DESCRIPTION
Корректно останавливает все компоненты системы мониторинга и очищает ресурсы.
#>
function Stop-ProcessMonitoring {
    Write-LogMessage "🛑 Остановка мониторинга процессов..." -Color Yellow
    
    # Останавливаем основной цикл
    if ($global:MonitoringConfig) {
        $global:MonitoringConfig.IsRunning = $false
    }
    
    # Останавливаем мониторинг файлов
    Stop-HandlersWatcher
    
    # Отменяем WMI события
    try {
        $subscribers = Get-EventSubscriber -ErrorAction SilentlyContinue
        if ($subscribers) {
            $subscribers | Unregister-Event -Force
            Write-LogMessage "✅ WMI события отменены" -Color Green
        }
    }
    catch {
        Write-LogMessage "⚠️ Ошибка отмены WMI событий: $_" -Color Yellow
    }
    
    # Очищаем глобальные переменные
    $variablesToClean = @("MonitoringConfig", "ProcessHandlers", "TrackedProcesses", "HandlersWatcher")
    foreach ($var in $variablesToClean) {
        if (Get-Variable -Name $var -Scope Global -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $var -Scope Global -ErrorAction SilentlyContinue
        }
    }
    
    Write-LogMessage "✅ Мониторинг процессов остановлен" -Color Green
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                   КОНЕЦ СЕКЦИИ ОСНОВНОЙ ЛОГИКИ МОНИТОРИНГА                     
#endregion ═══════════════════════════════════════════════════════════════════════════════

# Подгружаем ServiceFunctions если доступен (только если Write-LogMessage недоступна)  
if (-not (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $PSScriptRoot "ServiceFunctions.ps1")) {
        . (Join-Path $PSScriptRoot "ServiceFunctions.ps1")
    }
    else {
        # Простая альтернативная функция логирования
        function Write-LogMessage {
            param([string]$Message, [ConsoleColor]$Color = "White")
            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
        }
    }
}

Write-LogMessage "✅ MonitoringEngine.ps1 загружен успешно" -Color Green -NoTimestamp