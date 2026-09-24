@echo off
cd /d "%~dp0.."
title Portable Offline Chat - Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_PortableAI-System\scripts\Setup-PortableAI.ps1"
if errorlevel 1 pause
