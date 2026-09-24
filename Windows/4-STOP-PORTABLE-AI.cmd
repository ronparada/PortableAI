@echo off
cd /d "%~dp0.."
title Stop Portable AI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_PortableAI-System\scripts\Stop-PortableAI.ps1"
