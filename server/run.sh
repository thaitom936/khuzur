#!/bin/sh
# Starts the khuzur game server. Usage: ./run.sh [config]
cd "$(dirname "$0")" || exit 1
export DB_HOST="${DB_HOST:-127.0.0.1}"
# Unified private server configuration. Legacy files are a migration fallback
# only; once .env exists it is the sole source of file-based configuration.
set -a
if [ -f .env ]; then
  . ./.env || exit 1
else
  if [ -f .env.chat ]; then . ./.env.chat || exit 1; fi
  if [ -f .env.rtc ]; then . ./.env.rtc || exit 1; fi
fi
set +a
export AGORA_TOKEN_PORT="${AGORA_TOKEN_PORT:-9760}"
AGORA_TOKEN_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))') || exit 1
export AGORA_TOKEN_SECRET
signer_pid=
if [ -n "${AGORA_APP_ID:-}" ] && [ -n "${AGORA_APP_CERTIFICATE:-}" ]; then
  python3 rtc/token_server.py &
  signer_pid=$!
fi
CHAT_MEDIA_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))') || exit 1
export CHAT_MEDIA_SECRET
python3 media/r2_server.py &
media_pid=$!
game_pid=
cleanup() {
  if [ -n "$signer_pid" ]; then kill "$signer_pid" 2>/dev/null || true; fi
  kill "$media_pid" 2>/dev/null || true
  if [ -n "$game_pid" ]; then kill "$game_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# Fail early on a bad certificate or occupied port, before starting the game.
sleep 1
if [ -n "$signer_pid" ]; then kill -0 "$signer_pid" 2>/dev/null || exit 1; fi
kill -0 "$media_pid" 2>/dev/null || exit 1
./skynet/skynet "etc/${1:-config}" &
game_pid=$!
wait "$game_pid"
