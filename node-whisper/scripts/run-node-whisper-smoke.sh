#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
REMOTE_USER="${1:-${NODE_WHISPER_REMOTE_USER:-}}"
REMOTE_HOST="${2:-${NODE_WHISPER_REMOTE_HOST:-}}"
SSH_KEY="${NODE_WHISPER_SSH_KEY:-${SSH_KEY:-$HOME/.ssh/node_whisper_win}}"
REMOTE_DIR="E:/Projects/node-whisper-runtime"
REMOTE_PS1="C:/Users/${REMOTE_USER}/smoke-test-node-whisper.ps1"
REMOTE_PY="${REMOTE_DIR}/smoke_test_faster_whisper.py"

[[ -n "$REMOTE_USER" ]] || { echo "Missing NODE_WHISPER_REMOTE_USER" >&2; exit 2; }
[[ -n "$REMOTE_HOST" ]] || { echo "Missing NODE_WHISPER_REMOTE_HOST" >&2; exit 2; }

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$REMOTE_DIR' | Out-Null\""

scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/smoke-test-node-whisper.ps1" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PS1}"

scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/smoke_test_faster_whisper.py" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PY}"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File \"$REMOTE_PS1\""
