#!/usr/bin/env bash
set -euo pipefail
SYSTEM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; ROOT="$(cd "$SYSTEM_ROOT/.." && pwd)"; RUNTIME_ROOT="$SYSTEM_ROOT/runtime"; MODEL_ROOT="$SYSTEM_ROOT/models"; DOWNLOAD_ROOT="$SYSTEM_ROOT/downloads"
mkdir -p "$RUNTIME_ROOT" "$MODEL_ROOT" "$DOWNLOAD_ROOT"
fail() { printf '\nError: %s\n' "$1" >&2; exit 1; }
hash_file() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print toupper($1)}'; else shasum -a 256 "$1" | awk '{print toupper($1)}'; fi; }
download() {
  url="$1"; destination="$2"; expected="$(printf '%s' "$3" | tr '[:lower:]' '[:upper:]')"
  if [ -f "$destination" ]; then current="$(hash_file "$destination")"; case ",$expected," in *",$current,"*) printf 'Already verified: %s\n' "$(basename "$destination")"; return;; esac; fi
  rm -f "$destination"; printf 'Downloading %s...\n' "$(basename "$destination")"
  curl -L --fail --retry 3 --retry-delay 3 -C - -o "$destination.part" "$url"; mv "$destination.part" "$destination"
  actual="$(hash_file "$destination")"; case ",$expected," in *",$actual,"*) :;; *) rm -f "$destination"; fail "Safety check failed for $(basename "$destination").";; esac
}
install_runtime() {
  name="$1"; url="$2"; expected="$3"; target="$RUNTIME_ROOT/$name"
  if [ -f "$target/llama-server" ]; then printf 'Runtime is already present: %s\n' "$name"; chmod +x "$target/llama-server" 2>/dev/null || true; return; fi
  archive="$DOWNLOAD_ROOT/$name.tar.gz"; download "$url" "$archive" "$expected"
  rm -rf "$target"; mkdir -p "$target"; tar -xzf "$archive" -C "$target"
  server="$(find "$target" -type f -name llama-server | head -n 1)"; [ -n "$server" ] || fail "llama-server was not found after extracting $name."
  if [ "$server" != "$target/llama-server" ]; then inner="$(dirname "$server")"; cp -R "$inner"/. "$target"/; fi
  chmod +x "$target/llama-server"; if command -v xattr >/dev/null 2>&1; then xattr -dr com.apple.quarantine "$target" 2>/dev/null || true; fi
}
install_model() { download "$1" "$MODEL_ROOT/$3" "$2"; }
printf '\nPortable Offline Chat - first-time setup\n'
printf '\n'
printf '1. Standard setup: Qwen 3 4B only (recommended, about 2.7 GB)\n'
printf '2. Complete setup: Qwen 3 4B + Nous Hermes 3 3B model (about 4.7 GB)\n'
printf '3. Nous Hermes 3 3B model only (about 2.2 GB)\n'
printf 'Choose 1, 2, or 3 [1]: '; IFS= read -r answer || answer=1
case "${answer:-1}" in 2) choice=all;; 3) choice=hermes;; *) choice=qwen;; esac
os="$(uname -s)"; arch="$(uname -m)"
case "$os:$arch" in
  Darwin:arm64) install_runtime macos-arm64 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-macos-arm64.tar.gz' '033C845C1DF9BF945FF37BB193238B40910B2244BE3E1E637B2CEB5878F1A6F5';;
  Darwin:x86_64) install_runtime macos-x64 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-macos-x64.tar.gz' '03430A394D0A169A5E6D8F01C09F48CF58EB026AF6FC95940A4A528E2E50CF38';;
  Linux:x86_64|Linux:amd64) install_runtime linux-x64 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-ubuntu-x64.tar.gz' '9ABF88AEA48A55D0F80EDB1EE20220B186848CCA0B4E919D71518CFD7CA67443';;
  Linux:aarch64|Linux:arm64) install_runtime linux-arm64 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-ubuntu-arm64.tar.gz' '5F0E9C95D970892E43380F82EBCAB960EDFD20A1CD0F7ABFFA13B29FDB924949';;
  *) fail "Unsupported system: $os $arch";;
esac
if [ "$choice" = all ] || [ "$choice" = qwen ]; then install_model 'https://huggingface.co/bartowski/Qwen_Qwen3-4B-GGUF/resolve/main/Qwen_Qwen3-4B-Q4_K_M.gguf?download=true' 'FBE1D5EDD4CE802AE3AE7C7E4AB7D09789D697FDAC1FC7929F8DF4CA3C41BAE3,7485FE6F11AF29433BC51CAB58009521F205840F5B4AE3A32FA7F92E8534FDF5' 'Qwen3-4B-Q4_K_M.gguf'; fi
if [ "$choice" = all ] || [ "$choice" = hermes ]; then install_model 'https://huggingface.co/bartowski/Hermes-3-Llama-3.2-3B-GGUF/resolve/main/Hermes-3-Llama-3.2-3B-Q4_K_M.gguf?download=true' '2E220A14BA4328FEE38CF36C2C068261560F999FADB5725CE5C6D977CB5126B5' 'Hermes-3-Llama-3.2-3B-Q4_K_M.gguf'; fi
printf '\nPortable chat setup finished. You may disconnect from the internet.\n'
printf 'Return to your operating-system folder and open a START file.\n'
