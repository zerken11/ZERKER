#!/usr/bin/env bash
set -euo pipefail
# Use externally provided PORT or default
export PORT="${PORT:-3000}"
# Avoid failing when $PORT not interpolated in RUN_CMD; inject if common flags missing
CMD="npm run start"
exec bash -lc "$CMD"