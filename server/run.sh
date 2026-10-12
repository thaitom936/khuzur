#!/bin/sh
# Starts the khuzur game server. Usage: ./run.sh [config]
cd "$(dirname "$0")" || exit 1
export DB_HOST="${DB_HOST:-127.0.0.1}"
# Optional RTC: source a private server-only environment file.
if [ -f .env.rtc ]; then
  set -a
  . ./.env.rtc
  set +a
fi
if [ -z "${AGORA_APP_ID:-}" ] || [ -z "${AGORA_APP_CERTIFICATE:-}" ]; then
  exec ./skynet/skynet "etc/${1:-config}"
fi
export AGORA_TOKEN_PORT="${AGORA_TOKEN_PORT:-9760}"
AGORA_TOKEN_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))') || exit 1
export AGORA_TOKEN_SECRET
python3 rtc/token_server.py &
signer_pid=$!
game_pid=
cleanup() {
  kill "$signer_pid" 2>/dev/null || true
  if [ -n "$game_pid" ]; then kill "$game_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# Fail early on a bad certificate or occupied port, before starting the game.
sleep 1
kill -0 "$signer_pid" 2>/dev/null || exit 1
./skynet/skynet "etc/${1:-config}" &
game_pid=$!
wait "$game_pid"

