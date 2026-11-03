#!/usr/bin/env bash
set -euo pipefail

PORT="${QBO_GAME_PORT:-7000}"
# VPS dùng chung với app khác: giới hạn FPS để không đốt CPU (headless không
# có vsync nên mặc định có thể chạy hết tốc lực).
ARGS=(--headless --max-fps 60 --path /app/game -- --server "--port=${PORT}")

if [[ "${QBO_ALLOW_UNVERIFIED_TICKETS:-0}" == "1" ]]; then
  ARGS+=(--allow-unverified-tickets)
fi

echo "[qbo] dedicated server starting on UDP ${PORT}"
exec godot "${ARGS[@]}"
