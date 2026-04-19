#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${PROJECT_DIR:-}" ]; then
    echo "Usage: PROJECT_DIR=~/projects/my-app ./start.sh"
    echo "       Or set PROJECT_DIR in your environment."
    exit 1
fi

export PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
export PROJECT_HASH=$(printf '%s' "$PROJECT_DIR" | shasum | cut -c1-8)
export COMPOSE_PROJECT_NAME="claude-sandbox-$PROJECT_HASH"

docker compose build
docker compose up -d
echo ""
echo "Sandbox running. Project: $PROJECT_DIR"
echo "  PROJECT_DIR='$PROJECT_DIR' ./shell.sh  — enter the sandbox"
echo "  PROJECT_DIR='$PROJECT_DIR' ./stop.sh   — stop the sandbox"
echo "  claude --dangerously-skip-permissions"
