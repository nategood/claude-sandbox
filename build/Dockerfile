FROM node:20-bookworm-slim

ARG CLAUDE_CODE_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl sudo ca-certificates gnupg openssh-client \
    zsh ripgrep jq tree htop unzip build-essential \
    python3 python3-pip python3-venv \
    iptables ipset dnsutils iproute2 \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
RUN corepack enable && corepack prepare pnpm@latest --activate

RUN mkdir -p /home/node/.claude /commandhistory \
    && chown -R node:node /home/node /commandhistory

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

RUN echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
    && chmod 0440 /etc/sudoers.d/node-firewall

RUN npx playwright install-deps chromium
RUN npm install -g playwright

USER node
RUN npx playwright install chromium

WORKDIR /workspace
