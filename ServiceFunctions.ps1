# ServiceFunctions.ps1 - Universal PowerShell Service Toolkit
# Универсальный набор сервисных функций для любых PowerShell проектов
# 
# Возможности:
# - Проверка и запрос прав администратора
# - Предотвращение множественного запуска (mutex)
# - Автозагрузка через Task Scheduler
# - Проверка ExecutionPolicy
# - Базовое логирование
#
# Использование:
# . "path/to/ServiceFunctions.ps1"
# if (-not (Test-AdminRights)) { Request-AdminRights }

#region ═══════════════════════════════════════════════════════════════════════════════════
#region                           🔐 ПРАВА АДМИНИСТРАТОРА                                  
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Проверяет, запущен ли скрипт с правами администратора.

.DESCRIPTION
Проверяет текущие права выполнения и определяет является ли текущий пользователь администратором.

.EXAMPLE
if (Test-AdminRights) {
    Write-Host "Запущен с правами администратора"
} else {
    Write-Host "Запущен от обычного пользователя"
}

.OUTPUTS
[bool] - True если запущен от администратора, False если от обычного пользователя
#>
function Test-AdminRights {
    try {
        $currentPrincipal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    }
    catch {
        Write-Warning "Ошибка проверки прав администратора: $_"
        return $false
    }
}

<#
.SYNOPSIS
Запрашивает повышение прав до администратора и перезапускает скрипт.

.DESCRIPTION
Если скрипт запущен не от администратора, предлагает перезапустить с повышенными правами.
При согласии пользователя перезапускает скрипт через UAC и завершает текущий процесс.

.PARAMETER ScriptPath
Путь к скрипту для перезапуска. Если не указан, используется $PSCommandPath.

.PARAMETER Force
Принудительный перезапуск без запроса пользователя.

.EXAMPLE
# Запрос с подтверждением
if (-not (Test-AdminRights)) { Request-AdminRights }

.EXAMPLE  
# Принудительный перезапуск
if (-not (Test-AdminRights)) { Request-AdminRights -Force }

.EXAMPLE
# Перезапуск конкретного скрипта
Request-AdminRights -ScriptPath "C:\Scripts\MyScript.ps1"

.OUTPUTS
[bool] - True если уже админ, False если отказался от перезапуска, exit если перезапускается
#>
function Request-AdminRights {
    param(
        [string]$ScriptPath = $PSCommandPath,
        [switch]$Force
    )
    
    if (Test-AdminRights) {
        Write-LogMessage "✅ Запущен с правами администратора" -Color Green
        return $true
    }
    
    Write-LogMessage "⚠️ Скрипт запущен без прав администратора" -Color Yellow
    
    if (-not $Force) {
        Write-Host ""
        $choice = Read-Host "Перезапустить от имени администратора? (Y/N)"
        
        if ($choice -notmatch '^[Yy]') {
            Write-LogMessage "ℹ️ Продолжаем с правами текущего пользователя" -Color Blue
            return $false
        }
    }
    
    try {
        $scriptDir = Split-Path $ScriptPath -Parent
        
        Write-LogMessage "🔍 Поиск bat файла для повышения прав..." -Color Cyan
        
        # Ищем bat файл в той же папке  
        $batName = "RunAsAdmin.bat"
        
        $batFile = $null
        $batPath = Join-Path $scriptDir $batName
        Write-LogMessage "   Проверка: $batName" -Color Gray
        if (Test-Path $batPath) {
            $batFile = $batPath
            Write-LogMessage "   ✅ Найден!" -Color Green
            break
        }
        else {
            Write-LogMessage "   ❌ Не найден" -Color Red
        }
   
        
        if ($batFile) {
            Write-LogMessage "🎯 Запуск bat файла: $(Split-Path $batFile -Leaf)" -Color Green
            Write-LogMessage "📁 Рабочая папка: $scriptDir" -Color Cyan
            
            # ГЛАВНОЕ - ЗАПУСКАЕМ BAT ФАЙЛ
            Start-Process -FilePath $batFile -WorkingDirectory $scriptDir
            
            # # Завершаем текущий процесс
            # Write-LogMessage "🔄 Завершение текущего экземпляра..." -Color Yellow
            # Write-LogMessage "👀 Следите за новым окном с правами администратора" -Color Cyan
            # Start-Sleep -Seconds 2
            # exit 0
        }
        else {
            Write-LogMessage "❌ Bat файл для повышения прав не найден!" -Color Red
            Write-LogMessage "📁 Папка поиска: $scriptDir" -Color Gray
            Write-LogMessage "💡 Создайте файл RunAsAdmin.bat для автоматического повышения прав" -Color Cyan
            return $false
        }
        
    }
    catch {
        Write-LogMessage "❌ Ошибка запуска bat файла: $_" -Color Red
        return $false
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                    КОНЕЦ СЕКЦИИ ПРАВ АДМИНИСТРАТОРА                            
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                         🔒 ПРЕДОТВРАЩЕНИЕ ДУБЛИРОВАНИЯ                            
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Проверяет, запущен ли уже экземпляр скрипта.

.DESCRIPTION
Использует системный mutex для определения наличия уже запущенного экземпляра скрипта.

.PARAMETER MutexName
Имя mutex для проверки. Если не указано, генерируется на основе имени скрипта.

.EXAMPLE
if (Test-ScriptAlreadyRunning) {
    Write-Host "Скрипт уже запущен!"
}

.EXAMPLE
if (Test-ScriptAlreadyRunning -MutexName "MyCustomMutex") {
    Stop-ExistingScript
}

.OUTPUTS
[bool] - True если скрипт уже запущен, False если это первый экземпляр
#>
function Test-ScriptAlreadyRunning {
    param(
        [string]$MutexName = "Global\Script_$((Get-Item $PSCommandPath -ErrorAction SilentlyContinue).BaseName)_Mutex"
    )
    
    try {
        $global:ScriptMutex = New-Object System.Threading.Mutex($false, $MutexName)
        return (-not $global:ScriptMutex.WaitOne(0))
    }
    catch {
        Write-LogMessage "Ошибка при проверке mutex: $_" -Color Red
        return $false
    }
}

<#
.SYNOPSIS
Завершает все существующие экземпляры скрипта.

.DESCRIPTION
Находит и принудительно завершает все процессы PowerShell, которые выполняют тот же скрипт.

.PARAMETER ScriptPath
Путь к скрипту для поиска процессов. Если не указан, используется $PSCommandPath.

.PARAMETER TimeoutSeconds
Время ожидания завершения процессов в секундах. По умолчанию 5 секунд.

.EXAMPLE
Stop-ExistingScript

.EXAMPLE
Stop-ExistingScript -ScriptPath "C:\Scripts\MyScript.ps1" -TimeoutSeconds 10

.OUTPUTS
[int] - Количество завершенных процессов
#>
function Stop-ExistingScript {
    param(
        [string]$ScriptPath = $PSCommandPath,
        [int]$TimeoutSeconds = 5
    )
    
    $currentPID = $PID
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $terminatedCount = 0
    
    try {
        Write-LogMessage "🔍 Поиск существующих экземпляров скрипта..." -Color Yellow
        
        $existingProcesses = Get-WmiObject Win32_Process | Where-Object {
            $_.CommandLine -like "*$scriptName*" -and 
            $_.ProcessId -ne $currentPID -and
            $_.Name -eq "powershell.exe"
        }
        
        if ($existingProcesses) {
            foreach ($proc in $existingProcesses) {
                try {
                    Write-LogMessage "🔄 Завершение экземпляра (PID: $($proc.ProcessId))" -Color Yellow
                    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                    $terminatedCount++
                }
                catch {
                    Write-LogMessage "⚠️ Не удалось завершить процесс $($proc.ProcessId): $_" -Color Yellow
                }
            }
            
            if ($TimeoutSeconds -gt 0) {
                Write-LogMessage "⏳ Ожидание завершения процессов ($TimeoutSeconds сек)..." -Color Blue
                Start-Sleep -Seconds $TimeoutSeconds
            }
        }
        else {
            Write-LogMessage "ℹ️ Существующие экземпляры не найдены" -Color Blue
        }
        
        return $terminatedCount
    }
    catch {
        Write-LogMessage "❌ Ошибка при завершении существующих экземпляров: $_" -Color Red
        return $terminatedCount
    }
}

<#
.SYNOPSIS
Освобождает системный mutex при завершении скрипта.

.DESCRIPTION
Корректно освобождает и очищает mutex ресурсы. Должна вызываться в блоке finally или при завершении.

.EXAMPLE
try {
    # Основная логика
} finally {
    Release-ScriptMutex
}
#>
function Release-ScriptMutex {
    if ($global:ScriptMutex) {
        try {
            $global:ScriptMutex.ReleaseMutex()
            $global:ScriptMutex.Dispose()
            Remove-Variable -Name "ScriptMutex" -Scope Global -ErrorAction SilentlyContinue
            Write-LogMessage "✅ Mutex освобожден" -Color Green
        }
        catch {
            Write-LogMessage "⚠️ Ошибка при освобождении mutex: $_" -Color Yellow
        }
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                  КОНЕЦ СЕКЦИИ ПРЕДОТВРАЩЕНИЯ ДУБЛИРОВАНИЯ                      
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                              🚀 АВТОЗАГРУЗКА                                       
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Добавляет скрипт в автозагрузку Windows.

.DESCRIPTION
Создает задачу в Task Scheduler для автоматического запуска скрипта при входе в систему.
Если запущен от администратора, создает задачу с повышенными правами.

.PARAMETER ScriptPath
Путь к скрипту для автозагрузки. Если не указан, используется $PSCommandPath.

.PARAMETER TaskName
Имя задачи в Task Scheduler. Если не указано, генерируется на основе имени скрипта.

.PARAMETER RunAsAdmin
Запускать задачу с правами администратора. По умолчанию определяется автоматически.

.EXAMPLE
Add-ToStartup

.EXAMPLE
Add-ToStartup -ScriptPath "C:\Scripts\MyScript.ps1" -TaskName "MyCustomTask"

.EXAMPLE
Add-ToStartup -RunAsAdmin $true

.OUTPUTS
[bool] - True если успешно добавлено, False при ошибке
#>function Request-AdminRights {
    param(
        [string]$ScriptPath = $PSCommandPath,
        [switch]$Force
    )
    
    if (Test-AdminRights) {
        Write-LogMessage "✅ Запущен с правами администратора" -Color Green
        return $true
    }
    
    Write-LogMessage "⚠️ Скрипт запущен без прав администратора" -Color Yellow
    
    if (-not $Force) {
        Write-Host ""
        $choice = Read-Host "Перезапустить от имени администратора? (Y/N)"
        
        if ($choice -notmatch '^[Yy]') {
            Write-LogMessage "ℹ️ Продолжаем с правами текущего пользователя" -Color Blue
            return $false
        }
    }
    
    try {
        $scriptDir = Split-Path $ScriptPath -Parent
        
        Write-LogMessage "🔍 Поиск bat файла для повышения прав..." -Color Cyan
        
        # Ищем bat файл в той же папке  
        $possibleBatFiles = @(
            "RunAsAdmin.bat",
            "Admin.bat", 
            "Elevator.bat",
            "UAC.bat"
        )
        
        $batFile = $null
        foreach ($batName in $possibleBatFiles) {
            $batPath = Join-Path $scriptDir $batName
            Write-LogMessage "   Проверка: $batName" -Color Gray
            if (Test-Path $batPath) {
                $batFile = $batPath
                Write-LogMessage "   ✅ Найден!" -Color Green
                break
            }
            else {
                Write-LogMessage "   ❌ Не найден" -Color Red
            }
        }
        
        # Если не нашли стандартные имена, ищем любой .bat файл
        if (-not $batFile) {
            Write-LogMessage "   Поиск любых .bat файлов..." -Color Yellow
            $allBatFiles = Get-ChildItem -Path $scriptDir -Filter "*.bat" -ErrorAction SilentlyContinue
            if ($allBatFiles.Count -gt 0) {
                $batFile = $allBatFiles[0].FullName
                Write-LogMessage "   ✅ Найден: $($allBatFiles[0].Name)" -Color Green
            }
        }
        
        if ($batFile) {
            Write-LogMessage "🎯 Запуск bat файла: $(Split-Path $batFile -Leaf)" -Color Green
            Write-LogMessage "📁 Рабочая папка: $scriptDir" -Color Cyan
            
            # ГЛАВНОЕ - ЗАПУСКАЕМ BAT ФАЙЛ
            Start-Process -FilePath $batFile -WorkingDirectory $scriptDir
            
            # Завершаем текущий процесс
            Write-LogMessage "🔄 Завершение текущего экземпляра..." -Color Yellow
            Write-LogMessage "👀 Следите за новым окном с правами администратора" -Color Cyan
            Start-Sleep -Seconds 2
            exit 0
        }
        else {
            Write-LogMessage "❌ Bat файл для повышения прав не найден!" -Color Red
            Write-LogMessage "📁 Папка поиска: $scriptDir" -Color Gray
            Write-LogMessage "💡 Создайте файл RunAsAdmin.bat для автоматического повышения прав" -Color Cyan
            return $false
        }
        
    }
    catch {
        Write-LogMessage "❌ Ошибка запуска bat файла: $_" -Color Red
        return $false
    }
}
function Add-ToStartup {
    param(
        [string]$ScriptPath = $PSCommandPath,
        [string]$TaskName = "AutoStart_$([System.IO.Path]::GetFileNameWithoutExtension($ScriptPath))",
        [bool]$RunAsAdmin = (Test-AdminRights)
    )

    try {
        # Проверяем существование задачи
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

        # Команда и аргументы в правильной форме
        $command = "PowerShell.exe"
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

        if ($existingTask) {
            Write-LogMessage "🔄 Обновление существующей задачи автозагрузки..." -Color Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }

        # Создаем новую задачу
        Write-LogMessage "➕ Создание задачи автозагрузки: $TaskName" -Color Cyan

        $action = New-ScheduledTaskAction -Execute $command -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -AtLogOn

        if ($RunAsAdmin) {
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            Write-LogMessage "🔐 Задача будет запускаться с правами администратора" -Color Yellow
        }
        else {
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
            Write-LogMessage "👤 Задача будет запускаться с правами пользователя" -Color Blue
        }

        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Description "Автозапуск $([System.IO.Path]::GetFileName($ScriptPath))" | Out-Null

        Write-LogMessage "✅ Скрипт добавлен в автозагрузку" -Color Green
        return $true
    }
    catch {
        Write-LogMessage "❌ Ошибка при добавлении в автозагрузку: $_" -Color Red
        return $false
    }
}


<#
.SYNOPSIS
Удаляет скрипт из автозагрузки Windows.

.DESCRIPTION
Удаляет задачу из Task Scheduler.

.PARAMETER TaskName
Имя задачи для удаления. Если не указано, генерируется на основе текущего скрипта.

.PARAMETER ScriptPath
Путь к скрипту (используется для генерации имени задачи). Если не указан, используется $PSCommandPath.

.EXAMPLE
Remove-FromStartup

.EXAMPLE
Remove-FromStartup -TaskName "MyCustomTask"

.OUTPUTS
[bool] - True если успешно удалено, False при ошибке
#>
function Remove-FromStartup {
    param(
        [string]$TaskName = "AutoStart_$([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath))",
        [string]$ScriptPath = $PSCommandPath
    )
    
    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if ($existingTask) {
            Write-LogMessage "🗑️ Удаление задачи автозагрузки: $TaskName" -Color Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-LogMessage "✅ Скрипт удален из автозагрузки" -Color Green
            return $true
        }
        else {
            Write-LogMessage "ℹ️ Задача автозагрузки не найдена" -Color Blue
            return $true
        }
    }
    catch {
        Write-LogMessage "❌ Ошибка при удалении из автозагрузки: $_" -Color Red
        return $false
    }
}

<#
.SYNOPSIS
Проверяет, добавлен ли скрипт в автозагрузку.

.DESCRIPTION
Проверяет наличие задачи в Task Scheduler для текущего скрипта.

.PARAMETER TaskName
Имя задачи для проверки. Если не указано, генерируется на основе текущего скрипта.

.EXAMPLE
if (Test-InStartup) {
    Write-Host "Скрипт в автозагрузке"
}

.OUTPUTS
[bool] - True если находится в автозагрузке, False если нет
#>
function Test-InStartup {
    param(
        [string]$ScriptPath = $PSCommandPath,
        [string]$TaskName = "AutoStart_$([System.IO.Path]::GetFileNameWithoutExtension($ScriptPath))"
    )
    
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        return ($null -ne $task)
    }
    catch {
        return $false
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                           КОНЕЦ СЕКЦИИ АВТОЗАГРУЗКИ                            
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                          ⚙️ СИСТЕМНЫЕ ПРОВЕРКИ                                     
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Проверяет политику выполнения PowerShell скриптов.

.DESCRIPTION
Определяет, разрешено ли выполнение PowerShell скриптов согласно текущей ExecutionPolicy.

.PARAMETER Scope
Область для проверки политики. По умолчанию проверяется эффективная политика.

.EXAMPLE
if (-not (Test-ExecutionPolicy)) {
    Write-Host "Выполнение скриптов запрещено!"
}

.OUTPUTS
[bool] - True если выполнение разрешено, False если запрещено
#>
function Test-ExecutionPolicy {
    param(
        [string]$Scope = "Process"
    )
    
    try {
        $policy = Get-ExecutionPolicy -Scope $Scope
        $restrictive = @("Restricted", "AllSigned")
        
        if ($policy -in $restrictive) {
            Write-LogMessage "⚠️ ExecutionPolicy ($policy) ограничивает выполнение скриптов" -Color Yellow
            Write-LogMessage "💡 Выполните: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -Color Cyan
            return $false
        }
        
        Write-LogMessage "✅ ExecutionPolicy ($policy) разрешает выполнение скриптов" -Color Green
        return $true
    }
    catch {
        Write-LogMessage "❌ Ошибка проверки ExecutionPolicy: $_" -Color Red
        return $false
    }
}

<#
.SYNOPSIS
Устанавливает политику выполнения PowerShell скриптов.

.DESCRIPTION
Пытается установить ExecutionPolicy для разрешения выполнения скриптов.

.PARAMETER Policy
Политика для установки. По умолчанию RemoteSigned.

.PARAMETER Scope
Область применения политики. По умолчанию CurrentUser.

.EXAMPLE
Set-ExecutionPolicyIfNeeded

.EXAMPLE
Set-ExecutionPolicyIfNeeded -Policy "Bypass" -Scope "Process"

.OUTPUTS
[bool] - True если политика установлена успешно, False при ошибке
#>
function Set-ExecutionPolicyIfNeeded {
    param(
        [string]$Policy = "RemoteSigned",
        [string]$Scope = "CurrentUser"
    )
    
    if (Test-ExecutionPolicy) {
        return $true
    }
    
    try {
        Write-LogMessage "🔧 Установка ExecutionPolicy: $Policy (Scope: $Scope)" -Color Cyan
        Set-ExecutionPolicy -ExecutionPolicy $Policy -Scope $Scope -Force
        
        if (Test-ExecutionPolicy) {
            Write-LogMessage "✅ ExecutionPolicy успешно установлена" -Color Green
            return $true
        }
        else {
            Write-LogMessage "⚠️ ExecutionPolicy установлена, но проверка не прошла" -Color Yellow
            return $false
        }
    }
    catch {
        Write-LogMessage "❌ Ошибка установки ExecutionPolicy: $_" -Color Red
        Write-LogMessage "💡 Попробуйте запустить от имени администратора" -Color Cyan
        return $false
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                       КОНЕЦ СЕКЦИИ СИСТЕМНЫХ ПРОВЕРОК                          
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                            📝 ЛОГИРОВАНИЕ                                          
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Выводит сообщение с временной меткой и цветом.

.DESCRIPTION
Универсальная функция логирования с поддержкой цветов и временных меток.

.PARAMETER Message
Текст сообщения для вывода.

.PARAMETER Color
Цвет текста. По умолчанию White.

.PARAMETER Level
Уровень логирования (INFO, WARN, ERROR, etc.). Необязательный.

.PARAMETER NoTimestamp
Отключить вывод временной метки.

.EXAMPLE
Write-LogMessage "Скрипт запущен" -Color Green

.EXAMPLE
Write-LogMessage "Внимание!" -Color Yellow -Level "WARN"

.EXAMPLE
Write-LogMessage "Ошибка соединения" -Color Red -Level "ERROR"
#>
function Write-LogMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White",
        [string]$Level = "",
        [switch]$NoTimestamp
    )
    
    $output = ""
    
    # Добавляем временную метку
    if (-not $NoTimestamp) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $output += "[$timestamp] "
    }
    
    # Добавляем уровень
    if ($Level) {
        $output += "[$Level] "
    }
    
    # Добавляем сообщение
    $output += $Message
    
    Write-Host $output -ForegroundColor $Color
}

<#
.SYNOPSIS
Создает разделитель в логах.

.DESCRIPTION
Выводит красивый разделитель для структурирования логов.

.PARAMETER Title
Заголовок разделителя. Необязательный.

.PARAMETER Width
Ширина разделителя. По умолчанию 60 символов.

.PARAMETER Color
Цвет разделителя. По умолчанию Cyan.

.EXAMPLE
Write-LogSeparator

.EXAMPLE
Write-LogSeparator -Title "ИНИЦИАЛИЗАЦИЯ"

.EXAMPLE
Write-LogSeparator -Title "ЗАВЕРШЕНИЕ" -Color Red
#>
function Write-LogSeparator {
    param(
        [string]$Title = "",
        [int]$Width = 60,
        [ConsoleColor]$Color = "Cyan"
    )
    
    $separator = "═" * $Width
    
    if ($Title) {
        $padding = [Math]::Max(0, ($Width - $Title.Length - 2) / 2)
        $titleLine = "═" * [Math]::Floor($padding) + " $Title " + "═" * [Math]::Ceiling($padding)
        Write-Host $titleLine -ForegroundColor $Color
    }
    else {
        Write-Host $separator -ForegroundColor $Color
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                         КОНЕЦ СЕКЦИИ ЛОГИРОВАНИЯ                               
#endregion ═══════════════════════════════════════════════════════════════════════════════


#region ═══════════════════════════════════════════════════════════════════════════════════
#region                        🛠️ УТИЛИТЫ И ПОМОЩНИКИ                                      
#region ═══════════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
Создает папку если она не существует.

.DESCRIPTION
Безопасно создает папку с проверкой существования и обработкой ошибок.

.PARAMETER Path
Путь к создаваемой папке.

.PARAMETER ShowMessages
Показывать сообщения о создании папки. По умолчанию True.

.EXAMPLE
Ensure-Directory -Path "C:\MyApp\Logs"

.EXAMPLE
Ensure-Directory -Path "ProcessHandlers" -ShowMessages $false

.OUTPUTS
[bool] - True если папка существует или создана, False при ошибке
#>
function Ensure-Directory {
    param(
        [string]$Path,
        [bool]$ShowMessages = $true
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            if ($ShowMessages) {
                Write-LogMessage "📁 Создана папка: $Path" -Color Cyan
            }
        }
        return $true
    }
    catch {
        if ($ShowMessages) {
            Write-LogMessage "❌ Ошибка создания папки $Path`: $_" -Color Red
        }
        return $false
    }
}

<#
.SYNOPSIS
Получает информацию о текущем скрипте.

.DESCRIPTION
Возвращает различную информацию о выполняемом скрипте.

.EXAMPLE
$info = Get-ScriptInfo
Write-Host "Скрипт: $($info.Name)"
Write-Host "Папка: $($info.Directory)"

.OUTPUTS
[PSCustomObject] - Объект с информацией о скрипте
#>
function Get-ScriptInfo {
    $scriptPath = $PSCommandPath
    
    return [PSCustomObject]@{
        FullPath  = $scriptPath
        Directory = Split-Path $scriptPath -Parent
        Name      = Split-Path $scriptPath -Leaf
        BaseName  = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        Extension = [System.IO.Path]::GetExtension($scriptPath)
    }
}

#endregion ═══════════════════════════════════════════════════════════════════════════════
#endregion                    КОНЕЦ СЕКЦИИ УТИЛИТ И ПОМОЩНИКОВ                            
#endregion ═══════════════════════════════════════════════════════════════════════════════


# 🎯 ЭКСПОРТ ФУНКЦИЙ (для явного контроля экспорта в модулях)
# Раскомментируйте и используйте Export-ModuleMember если создаете .psm1 модуль

# Export-ModuleMember -Function @(
#     'Test-AdminRights',
#     'Request-AdminRights', 
#     'Test-ScriptAlreadyRunning',
#     'Stop-ExistingScript',
#     'Release-ScriptMutex',
#     'Add-ToStartup',
#     'Remove-FromStartup', 
#     'Test-InStartup',
#     'Test-ExecutionPolicy',
#     'Set-ExecutionPolicyIfNeeded',
#     'Write-LogMessage',
#     'Write-LogSeparator',
#     'Ensure-Directory',
#     'Get-ScriptInfo'
# )

Write-LogMessage "✅ ServiceFunctions.ps1 загружен успешно" -Color Green -NoTimestamp