@echo off
cd /d "%~dp0.."
title PortableAI - Lab Assistant
set /p "LAB_ROOT=Enter the full path of the lab folder (or drag it here): "
set "LAB_ROOT=%LAB_ROOT:"=%"
if not defined LAB_ROOT (
  echo A lab folder is required.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_PortableAI-System\scripts\Start-PortableAI.ps1" -Model qwen -NoBrowser -LabRoot "%LAB_ROOT%"
if errorlevel 1 pause
