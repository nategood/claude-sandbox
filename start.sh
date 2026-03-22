#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${PROJECT_DIR:-}" ]; then
    echo "Usage: PROJECT_DIR=~/projects/my-app ./start.sh"
    echo "       Or set PROJECT_DIR in your environment."
    exit 1
fi

export PROJECT_DIR
docker compose build
docker compose up -d
echo ""
echo "Sandbox running. Project: $PROJECT_DIR"
echo "  ./shell.sh            — enter the sandbox"
echo "  claude --dangerously-skip-permissions"
