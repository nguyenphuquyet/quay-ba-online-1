#!/usr/bin/env bash
set -euo pipefail

PORT="${QBO_GAME_PORT:-7000}"

# Godot cần cache import (.godot/) trước khi chạy project từ source. Nếu volume
# cache bị xoá hoặc mount rỗng, chạy import một lần rồi mới start để tránh
# crash-loop vì thiếu global class cache.
if [[ ! -f /app/game/.godot/global_script_class_cache.cfg ]]; then
  echo "[qbo] chưa có cache import — đang import asset lần đầu (có thể mất vài phút)..."
  godot --headless --path /app/game --import >/dev/null 2>&1 || true
fi
# VPS dùng chung với app khác: giới hạn FPS để không đốt CPU (headless không
# có vsync nên mặc định có thể chạy hết tốc lực).
ARGS=(--headless --max-fps 60 --path /app/game -- --server "--port=${PORT}")

if [[ "${QBO_ALLOW_UNVERIFIED_TICKETS:-0}" == "1" ]]; then
  ARGS+=(--allow-unverified-tickets)
fi

echo "[qbo] dedicated server starting on UDP ${PORT}"
exec godot "${ARGS[@]}"
