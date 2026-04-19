#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${PROJECT_DIR:-}" ]; then
    echo "Usage: PROJECT_DIR=~/projects/my-app ./stop.sh"
    exit 1
fi

export PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
export PROJECT_HASH=$(printf '%s' "$PROJECT_DIR" | shasum | cut -c1-8)
export COMPOSE_PROJECT_NAME="claude-sandbox-$PROJECT_HASH"

docker compose down
