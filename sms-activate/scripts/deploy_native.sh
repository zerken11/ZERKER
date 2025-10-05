#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-8080}"

# Minimal native run; assumes runtime installed.
if [[ -f package.json ]]; then
  if command -v npm >/dev/null 2>&1; then
    if [[ -f package-lock.json ]]; then npm ci --omit=dev; else npm install --omit=dev; fi
    export PORT
    nohup bash -lc 'npm run start 2>&1' >/var/log/app.log &
  elif command -v node >/dev/null 2>&1; then
    export PORT
    nohup bash -lc 'node index.js 2>&1' >/var/log/app.log &
  else
    echo "Node/npm not found."
    exit 1
  fi
elif [[ -f requirements.txt || -f pyproject.toml ]]; then
  PY="python3"; command -v python3 >/dev/null 2>&1 || PY="python"
  PIP="$PY -m pip"
  $PIP install --upgrade pip
  if [[ -f requirements.txt ]]; then $PIP install -r requirements.txt; fi
  export PORT
  # best-effort start (adjust as needed)
  if [[ -f app.py ]]; then nohup bash -lc "$PY -u app.py 2>&1" >/var/log/app.log &
  elif [[ -f main.py ]]; then nohup bash -lc "$PY -u main.py 2>&1" >/var/log/app.log &
  else echo "Set RUN_CMD."; exit 1; fi
else
  echo "Unknown project type."
  exit 1
fi

echo "Started app on port ${PORT} (native). Logs: /var/log/app.log"