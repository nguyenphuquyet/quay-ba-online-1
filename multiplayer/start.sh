#!/usr/bin/env bash
set -euo pipefail

PORT="${QBO_GAME_PORT:-7000}"
ARGS=(--headless --path /app/game -- --server "--port=${PORT}")

if [[ "${QBO_ALLOW_UNVERIFIED_TICKETS:-0}" == "1" ]]; then
  ARGS+=(--allow-unverified-tickets)
fi

echo "[qbo] dedicated server starting on UDP ${PORT}"
exec godot "${ARGS[@]}"
