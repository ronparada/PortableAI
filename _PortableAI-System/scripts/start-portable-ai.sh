#!/usr/bin/env bash
set -euo pipefail
SYSTEM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; ROOT="$(cd "$SYSTEM_ROOT/.." && pwd)"; MODEL="${1:-qwen}"; PORT=18765
mkdir -p "$SYSTEM_ROOT/data/logs" "$SYSTEM_ROOT/data/cache" "$SYSTEM_ROOT/data/temp"; export LLAMA_CACHE="$SYSTEM_ROOT/data/cache"; export TMPDIR="$SYSTEM_ROOT/data/temp"
case "$MODEL" in qwen) MODEL_FILE="$SYSTEM_ROOT/models/Qwen3-4B-Q4_K_M.gguf";; hermes) MODEL_FILE="$SYSTEM_ROOT/models/Hermes-3-Llama-3.2-3B-Q4_K_M.gguf";; *) printf 'Unknown model: %s\n' "$MODEL" >&2; exit 1;; esac
[ -f "$MODEL_FILE" ] || { printf 'The %s model is missing. Run step 1 in your operating-system folder first.\n' "$MODEL" >&2; exit 1; }
os="$(uname -s)"; arch="$(uname -m)"
case "$os:$arch" in
  Darwin:arm64) platform=macos-arm64; layers=99;; Darwin:x86_64) platform=macos-x64; layers=99;;
  Linux:x86_64|Linux:amd64) platform=linux-x64; layers=0;; Linux:aarch64|Linux:arm64) platform=linux-arm64; layers=0;;
  *) printf 'Unsupported system: %s %s\n' "$os" "$arch" >&2; exit 1;; esac
SERVER="$SYSTEM_ROOT/runtime/$platform/llama-server"; [ -f "$SERVER" ] || { printf 'The %s runtime is missing. Run step 1 in your operating-system folder first.\n' "$platform" >&2; exit 1; }
chmod +x "$SERVER" 2>/dev/null || true
PID_FILE="$SYSTEM_ROOT/data/server.pid"
if [ -f "$PID_FILE" ]; then
  old_pid="$(head -n 1 "$PID_FILE" 2>/dev/null || true)"
  if printf '%s' "$old_pid" | grep -Eq '^[0-9]+$' && kill -0 "$old_pid" 2>/dev/null; then
    old_command="$(ps -p "$old_pid" -o command= 2>/dev/null || true)"
    case "$old_command" in *"$SYSTEM_ROOT/runtime/"*llama-server*) printf 'Stopping a Portable AI server left open from the previous session...\n'; kill "$old_pid" 2>/dev/null || true; sleep 1;; esac
  fi
  rm -f "$PID_FILE"
fi
if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then printf 'Port %s is busy. Run 4-STOP-PORTABLE-AI.sh and try again.\n' "$PORT" >&2; exit 1; fi
"$SERVER" -m "$MODEL_FILE" --alias portable-ai --host 127.0.0.1 --port "$PORT" --cors-origins "http://127.0.0.1:$PORT,http://localhost:$PORT" --no-cors-credentials -c 8192 -ngl "$layers" --offline --reasoning off --no-webui-mcp-proxy --parallel 1 >"$SYSTEM_ROOT/data/logs/server-out.log" 2>"$SYSTEM_ROOT/data/logs/server-error.log" &
server_pid=$!; printf '%s\n' "$server_pid" > "$PID_FILE"
cleanup() { kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; rm -f "$PID_FILE"; }; trap cleanup EXIT HUP INT TERM
printf 'Loading %s. A USB drive can take a minute...\n' "$MODEL"; ready=0
for _ in $(seq 1 240); do
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  if curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"\|"status": "ok"'; then ready=1; break; fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then printf 'The model did not load. Recent log output:\n' >&2; tail -n 20 "$SYSTEM_ROOT/data/logs/server-error.log" >&2 || true; exit 1; fi
printf 'Ready: http://127.0.0.1:%s\n' "$PORT"
if [ "$os" = Darwin ]; then open "http://127.0.0.1:$PORT"; elif command -v xdg-open >/dev/null 2>&1; then xdg-open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true; fi
printf 'Keep this terminal open while chatting. Press Enter to stop the AI.\n'; IFS= read -r _
