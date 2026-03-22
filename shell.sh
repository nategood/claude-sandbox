#!/bin/bash
cd "$(dirname "$0")"
docker compose exec claude zsh -ic "claude --dangerously-skip-permissions; zsh"
