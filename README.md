# 🎯 ProcessMonitor - Elegant Process Handler System

> **Автоматическое выполнение пользовательских PowerShell скриптов при запуске и завершении процессов Windows**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)

## 🤔 Концепция

**ProcessMonitor** следит за запуском и завершением процессов Windows и **автоматически выполняет ваши PowerShell скрипты** в ответ на эти события.

**Простыми словами:**
- 📁 Вы кладете `.ps1` файл в папку `ProcessHandlers`  
- 🏷️ Называете его по имени процесса (например `notepad.ps1`)
- ⚡ ProcessMonitor **вызывает ваш скрипт** каждый раз когда блокнот запускается или закрывается
- 🎯 **Ваш скрипт получает всю информацию** о процессе и может делать что угодно


## ✨ Возможности

- 🔄 **Hot-reload** - добавляйте обработчики без перезапуска
- 🎯 **3 типа обработчиков**: universal, start-only, end-only  
- 🔐 **Умное повышение прав** - автоматический UAC через bat
- 🚀 **Автозагрузка** - Task Scheduler интеграция
- 📝 **Богатые примеры** - готовые шаблоны и документация
- ⚡ **WMI + Polling** - надежная работа в любых условиях

## 🚀 Быстрый старт

### Установка
```bash
git clone https://github.com/damix96/ProcessMonitor.git
cd ProcessMonitor
# запуск
.\ProcessMonitor.ps1
