#!/usr/bin/env bash
set -u
SYSTEM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; PID_FILE="$SYSTEM_ROOT/data/server.pid"; stopped=0
if [ -f "$PID_FILE" ]; then
  old_pid="$(head -n 1 "$PID_FILE" 2>/dev/null || true)"
  if printf '%s' "$old_pid" | grep -Eq '^[0-9]+$' && kill -0 "$old_pid" 2>/dev/null; then
    old_command="$(ps -p "$old_pid" -o command= 2>/dev/null || true)"
    case "$old_command" in *"$SYSTEM_ROOT/runtime/"*llama-server*) kill "$old_pid" 2>/dev/null || true; stopped=1;; esac
  fi
  rm -f "$PID_FILE"
fi
if [ "$stopped" -eq 1 ]; then printf 'Portable AI has been stopped. You may now start another model.\n'; else printf 'No Portable AI server from this folder is running.\n'; fi
