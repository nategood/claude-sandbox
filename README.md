# Claude Sandbox

A Docker-based sandbox for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with network isolation. The container runs Claude Code in a locked-down environment with iptables firewall rules that only allow DNS, HTTP/HTTPS, and SSH traffic — blocking all other outbound connections.

## Quick Start

```bash
# 1. Start the sandbox with a project mounted
PROJECT_DIR=~/projects/my-app ./start.sh

# 2. Enter the sandbox
./shell.sh

# 3. Authenticate (if not using an API key)
# Claude Code will prompt you to log in with your Claude subscription
```

## What's Included

- **Network firewall** — iptables rules allow only DNS, SSH, HTTP/HTTPS, and configurable host ports. Everything else is dropped.
- **Host port access** — connect to services on your host machine (databases, dev servers) through configurable port allowlist.
- **Tooling** — git, ripgrep, jq, tree, Python 3, pnpm, Playwright (Chromium).

## Scripts

| Script | Description |
|---|---|
| `start.sh` | Build and start the sandbox (requires `PROJECT_DIR`) |
| `shell.sh` | Open a shell in the running sandbox |
| `rebuild.sh` | Full rebuild with no cache |
| `stop.sh` | Stop the sandbox |

## Configuration

Environment variables can be set in `.env` or passed inline:

| Variable | Description | Default |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key (or just authenticate with Claude Max subscription) | — |
| `PROJECT_DIR` | Host directory to mount at `/workspace` | `.` |
| `HOST_PORTS` | Comma-separated ports/ranges to allow to the host | `3000,4000,8000,8080` |

```bash
# Example: override host ports at runtime
HOST_PORTS="5432,8080,9090" PROJECT_DIR=~/my-app ./start.sh
```

## Firewall Details

The init-firewall script (`build/init-firewall.sh`) runs at container startup and configures iptables:

**Allowed:**
- Loopback and established connections
- Docker embedded DNS (127.0.0.11)
- General DNS (port 53)
- SSH (port 22)
- HTTP/HTTPS (ports 80, 443)
- Configurable host machine ports

**Blocked:**
- All other outbound traffic (raw TCP, SMTP, etc.)

On environments where iptables is unavailable (e.g. Docker Desktop on macOS/Windows), the script exits gracefully and relies on Docker's built-in VM isolation.

## License

[MIT](LICENSE)
