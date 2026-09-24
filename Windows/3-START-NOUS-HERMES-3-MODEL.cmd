@echo off
cd /d "%~dp0.."
title Portable AI - Nous Hermes 3 Language Model
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_PortableAI-System\scripts\Start-PortableAI.ps1" -Model hermes
