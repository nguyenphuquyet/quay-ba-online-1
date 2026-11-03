#!/usr/bin/env bash
# Kiểm tra nhanh toàn repo. Không cần Docker/MySQL.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
FAILED=0

step() { printf '\n\033[1;36m== %s ==\033[0m\n' "$1"; }
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$1"; FAILED=1; }

step "Godot import"
if [[ -x "$GODOT_BIN" ]]; then
  "$GODOT_BIN" --headless --path "$ROOT/game" --editor --quit >/tmp/qbo-godot-import.log 2>&1
  if [[ $? -eq 0 ]]; then echo "OK"; else fail "godot import (xem /tmp/qbo-godot-import.log)"; fi

  step "Godot offline smoke test"
  "$GODOT_BIN" --headless --path "$ROOT/game" --fixed-fps 60 -- --smoke 2>&1 | tail -20
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then fail "smoke test"; else echo "OK"; fi
else
  echo "SKIP: không tìm thấy Godot tại $GODOT_BIN (đặt GODOT_BIN=...)"
fi

step "Backend Prisma validate/generate + typecheck + build"
if [[ -d "$ROOT/server/node_modules" ]]; then
  (
    cd "$ROOT/server"
    export DATABASE_URL="${DATABASE_URL:-mysql://qbo:qbo_dev_password@127.0.0.1:3306/quaybaronline}"
    ./node_modules/.bin/prisma validate || exit 1
    ./node_modules/.bin/prisma generate || exit 1
    ./node_modules/.bin/tsc --noEmit || exit 1
    ./node_modules/.bin/next build || exit 1
  )
  if [[ $? -ne 0 ]]; then fail "backend checks"; else echo "OK"; fi
else
  echo "SKIP: chưa cài server/node_modules (cd server && npm install)"
fi

step "Kết quả"
if [[ $FAILED -eq 0 ]]; then echo "PASS"; else echo "CÓ LỖI"; exit 1; fi
