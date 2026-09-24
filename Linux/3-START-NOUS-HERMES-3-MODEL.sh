#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/_PortableAI-System/scripts/start-portable-ai.sh" hermes
