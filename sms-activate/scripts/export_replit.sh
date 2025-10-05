# ====================================================================
# File: scripts/export_replit.sh
# ====================================================================
#!/usr/bin/env bash
set -euo pipefail

# --- defaults ---
APP_NAME=""
PORT=""
INCLUDE_ENV=0
PUSH_TARGET=""
RUN_CMD_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: scripts/export_replit.sh [options]

Options:
  -n, --name NAME        Application name (used for image/tag and export filename).
  -p, --port PORT        Service port to expose (default: 3000 for Node, 8000 for Python).
      --include-env      Export current environment into .env (be careful with secrets).
      --push TARGET      scp target to upload bundle, e.g. user@host:/var/www/.
      --run-cmd CMD      Override run command (skips .replit & heuristics).
  -h, --help             Show help.

Examples:
  scripts/export_replit.sh -n myapp
  scripts/export_replit.sh -n myapp -p 8080 --include-env --push user@vps:/opt/apps
  scripts/export_replit.sh -n api --run-cmd "python -m uvicorn app:app --host 0.0.0.0 --port \$PORT"
USAGE
}

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) APP_NAME="${2:-}"; shift 2;;
    -p|--port) PORT="${2:-}"; shift 2;;
    --include-env) INCLUDE_ENV=1; shift;;
    --push) PUSH_TARGET="${2:-}"; shift 2;;
    --run-cmd) RUN_CMD_OVERRIDE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

# --- helpers ---
die() { echo "Error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date +"%Y%m%d-%H%M%S"; }

read_json_field() {
  # $1: file, $2: jq-like field path but very simple "scripts.start" supported
  local f="$1" key="$2"
  python3 - "$f" "$key" <<'PY' || true
import json,sys
from functools import reduce
p=sys.argv[2].split('.')
with open(sys.argv[1]) as fh:
    try:
        d=json.load(fh)
    except Exception:
        sys.exit(1)
try:
    v=reduce(lambda a,k:a[k], p, d)
    print(v)
except Exception:
    sys.exit(1)
PY
}

extract_replit_run() {
  # naive parser for `.replit` run="..."
  [[ -f ".replit" ]] || return 1
  awk -F'=' '/^[[:space:]]*run[[:space:]]*=/{sub(/^[^=]*=/,"",$0); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$0); print $0}' .replit \
  | sed -E 's/^"(.+)"$/\1/' | head -n1
}

ensure_dir() { mkdir -p "$1"; }

write_file() {
  local path="$1"; shift
  ensure_dir "$(dirname "$path")"
  cat > "$path" <<'EOF'
EOF
  # replace file with provided heredoc content via printf to avoid nested EOF confusion
  # shellcheck disable=SC2059
  printf "%s" "$*" > "$path"
}

append_file() {
  local path="$1"; shift
  ensure_dir "$(dirname "$path")"
  printf "%s" "$*" >> "$path"
}

# --- detect language ---
LANGUAGE="unknown"
if [[ -f package.json ]]; then
  LANGUAGE="node"
elif [[ -f requirements.txt || -f pyproject.toml ]]; then
  LANGUAGE="python"
fi

# --- infer app name ---
if [[ -z "$APP_NAME" ]]; then
  if [[ "$LANGUAGE" == "node" && -f package.json ]]; then
    APP_NAME="$(read_json_field package.json name || true)"
  fi
  [[ -z "$APP_NAME" ]] && APP_NAME="$(basename "$PWD")"
fi
[[ -z "$APP_NAME" ]] && die "Could not determine app name. Use --name."

# --- default port ---
if [[ -z "$PORT" ]]; then
  case "$LANGUAGE" in
    node) PORT="3000";;
    python) PORT="8000";;
    *) PORT="8080";;
  esac
fi

# --- determine run command ---
RUN_CMD=""
if [[ -n "$RUN_CMD_OVERRIDE" ]]; then
  RUN_CMD="$RUN_CMD_OVERRIDE"
else
  # try .replit first
  RUN_CMD="$(extract_replit_run || true)"
  if [[ -z "$RUN_CMD" ]]; then
    case "$LANGUAGE" in
      node)
        START_SCRIPT="$(read_json_field package.json scripts.start || true)"
        if [[ -n "$START_SCRIPT" ]]; then
          RUN_CMD="npm run start"
        elif [[ -f index.js ]]; then
          RUN_CMD="node index.js"
        else
          RUN_CMD="node ."
        fi
        ;;
      python)
        # prefer common uvicorn default if FastAPI-like, else app.py/main.py
        if [[ -f app.py ]]; then RUN_CMD="python -u app.py"
        elif [[ -f main.py ]]; then RUN_CMD="python -u main.py"
        else RUN_CMD="python -c 'print(\"Define RUN_CMD or .replit run\")' && sleep infinity"
        fi
        ;;
      *)
        RUN_CMD="sh -c 'echo \"Define --run-cmd or include .replit run\"; sleep infinity'"
        ;;
    esac
  fi
fi

# Ensure RUN_CMD uses $PORT var if recognizable
# (No edit here; users can override if needed.)

echo "Detected:"
echo "  App:       $APP_NAME"
echo "  Language:  $LANGUAGE"
echo "  Port:      $PORT"
echo "  Run cmd:   $RUN_CMD"

# --- lock dependencies ---
if [[ "$LANGUAGE" == "node" ]]; then
  if [[ ! -f package.json ]]; then die "package.json missing"; fi
  if [[ ! -f package-lock.json && ! -f pnpm-lock.yaml && ! -f yarn.lock ]]; then
    if have npm; then
      echo "Generating package-lock.json..."
      npm i --package-lock-only >/dev/null 2>&1 || true
    fi
  fi
elif [[ "$LANGUAGE" == "python" ]]; then
  if [[ ! -f requirements.txt ]]; then
    if have python -o have python3 && have pip -o have pip3; then
      echo "Generating requirements.txt from current env..."
      ( (have python3 && python3 -m pip freeze) || (have python && python -m pip freeze) ) > requirements.txt || true
    else
      echo "pip not found; proceed without freezing requirements."
    fi
  fi
fi

# --- ops/start.sh ---
START_SH_CONTENT=$(cat <<EOS
#!/usr/bin/env bash
set -euo pipefail
# Use externally provided PORT or default
export PORT="\${PORT:-$PORT}"
# Avoid failing when \$PORT not interpolated in RUN_CMD; inject if common flags missing
CMD="$RUN_CMD"
exec bash -lc "\$CMD"
EOS
)
write_file "ops/start.sh" "$START_SH_CONTENT"
chmod +x ops/start.sh

# --- Dockerfile ---
if [[ "$LANGUAGE" == "node" ]]; then
  DOCKERFILE_CONTENT=$(cat <<'EOD'
# syntax=docker/dockerfile:1
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json* ./
COPY pnpm-lock.yaml* ./
COPY yarn.lock* ./
RUN \
  if [ -f package-lock.json ]; then npm ci --omit=dev; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable && pnpm i --frozen-lockfile --prod; \
  elif [ -f yarn.lock ]; then corepack enable && yarn install --frozen-lockfile --production; \
  else npm install --omit=dev; fi

FROM node:20-alpine AS runner
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
EXPOSE 3000
CMD ["sh", "-c", "./ops/start.sh"]
EOD
)
elif [[ "$LANGUAGE" == "python" ]]; then
  DOCKERFILE_CONTENT=$(cat <<'EOD'
# syntax=docker/dockerfile:1
FROM python:3.11-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements*.txt ./ || true
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi
COPY . .
EXPOSE 8000
CMD ["bash", "-lc", "./ops/start.sh"]
EOD
)
else
  DOCKERFILE_CONTENT=$(cat <<'EOD'
FROM alpine:3.20
WORKDIR /app
COPY . .
EXPOSE 8080
CMD ["sh","-c","./ops/start.sh"]
EOD
)
fi
write_file "Dockerfile" "$DOCKERFILE_CONTENT"

# --- docker-compose.yml ---
COMPOSE_CONTENT=$(cat <<EOC
services:
  ${APP_NAME}:
    build: .
    container_name: ${APP_NAME}
    environment:
      - PORT=\${PORT:-$PORT}
    ports:
      - "\${PORT:-$PORT}:\${PORT:-$PORT}"
    restart: unless-stopped
    command: ["bash","-lc","./ops/start.sh"]
EOC
)
write_file "docker-compose.yml" "$COMPOSE_CONTENT"

# --- .dockerignore ---
DOCKERIGNORE_CONTENT=$(cat <<'EODI'
.git
.gitignore
node_modules
.npm
.pnpm-store
.venv
__pycache__
*.pyc
.cache
tmp
replit_modules
EODI
)
write_file ".dockerignore" "$DOCKERIGNORE_CONTENT"

# --- optional env export ---
if [[ $INCLUDE_ENV -eq 1 ]]; then
  echo "Exporting current environment to .env (review manually to avoid leaking secrets)."
  printenv | sort > .env
fi

# --- include deploy scripts into repo (idempotent) ---
# deploy_docker.sh
DEPLOY_DOCKER=$(cat <<'EODK'
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
EODK
)
write_file "scripts/deploy_docker.sh" "$DEPLOY_DOCKER"
chmod +x scripts/deploy_docker.sh

# deploy_native.sh
DEPLOY_NATIVE=$(cat <<'EODN'
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
EODN
)
write_file "scripts/deploy_native.sh" "$DEPLOY_NATIVE"
chmod +x scripts/deploy_native.sh

# --- build export bundle ---
EXPORTS_DIR="exports"
ensure_dir "$EXPORTS_DIR"
ARCHIVE="${EXPORTS_DIR}/${APP_NAME}-$(timestamp).tgz"

echo "Creating archive: ${ARCHIVE}"
tar \
  --exclude='./node_modules' \
  --exclude='./.venv' \
  --exclude='./.git' \
  --exclude='./__pycache__' \
  --exclude='./.cache' \
  -czf "$ARCHIVE" \
  .

echo "Bundle ready: $ARCHIVE"

# --- optional push ---
if [[ -n "$PUSH_TARGET" ]]; then
  if ! have scp; then die "scp not found for --push"; fi
  echo "Pushing to $PUSH_TARGET ..."
  scp -q "$ARCHIVE" "$PUSH_TARGET"
  echo "Uploaded. On VPS:"
  echo "  tar -xzf $(basename "$ARCHIVE") && cd $(basename "$PWD")"
  echo "  ./scripts/deploy_docker.sh $APP_NAME $PORT"
fi

echo "Done."
