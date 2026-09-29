#!/bin/sh
# Starts the khuzur game server. Usage: ./run.sh [config]
cd "$(dirname "$0")" || exit 1
export DB_HOST="${DB_HOST:-127.0.0.1}"
exec ./skynet/skynet "etc/${1:-config}"
