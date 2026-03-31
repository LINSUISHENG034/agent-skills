#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./node_whisper_load_env.sh
source "$SCRIPT_DIR/node_whisper_load_env.sh"
REMOTE_USER="${1:-${NODE_WHISPER_REMOTE_USER:-}}"
REMOTE_HOST="${2:-${NODE_WHISPER_REMOTE_HOST:-}}"
SSH_KEY="${NODE_WHISPER_SSH_KEY:-${SSH_KEY:-$HOME/.ssh/node_whisper_win}}"
REMOTE_PS1="C:/Users/${REMOTE_USER}/node-whisper-probe.ps1"

[[ -n "$REMOTE_USER" ]] || { echo "Missing NODE_WHISPER_REMOTE_USER" >&2; exit 2; }
[[ -n "$REMOTE_HOST" ]] || { echo "Missing NODE_WHISPER_REMOTE_HOST" >&2; exit 2; }

scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "$SCRIPT_DIR/probe-node-whisper-env.ps1" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PS1}"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File \"$REMOTE_PS1\""
