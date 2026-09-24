@echo off
cd /d "%~dp0.."
title Portable AI - Qwen Chat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_PortableAI-System\scripts\Start-PortableAI.ps1" -Model qwen
