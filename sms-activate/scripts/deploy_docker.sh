#!/usr/bin/env bash
set -euo pipefail
APP_NAME="${1:-}"
PORT="${2:-}"
[[ -z "$APP_NAME" ]] && APP_NAME="$(basename "$PWD")"
[[ -z "$PORT" ]] && PORT="${PORT:-8080}"

have() { command -v "$1" >/dev/null 2>&1; }
die(){ echo "Error: $*" >&2; exit 1; }

if ! have docker; then die "Docker not found. Install Docker then retry."; fi
COMPOSE_BIN=""
if docker compose version >/dev/null 2>&1; then COMPOSE_BIN="docker compose"; fi
if [[ -z "$COMPOSE_BIN" ]] && command -v docker-compose >/dev/null 2>&1; then COMPOSE_BIN="docker-compose"; fi
[[ -z "$COMPOSE_BIN" ]] && die "docker compose not available."

export PORT="${PORT}"

$COMPOSE_BIN build
$COMPOSE_BIN up -d
$COMPOSE_BIN ps

echo "Deployed '$APP_NAME' on port ${PORT}."