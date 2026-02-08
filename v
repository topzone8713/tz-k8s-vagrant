#!/usr/bin/env bash
# Vagrant wrapper for Windows Git Bash: run with Windows cwd to avoid "path specified".
# Use: ./v status, ./v ssh kube-master, ./v destroy -f
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys2" ]]; then
  win_path=$(cygpath -w "$SCRIPT_DIR" 2>/dev/null) || win_path=$(echo "$SCRIPT_DIR" | sed 's|^/\([a-zA-Z]\)/|\1:\\|' | sed 's|/|\\|g')
  win_path_ps="${win_path//\'/\'\'}"
  powershell -NoProfile -NonInteractive -Command "Set-Location -LiteralPath '$win_path_ps'; vagrant $*"
else
  exec vagrant "$@"
fi
