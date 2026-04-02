#!/bin/bash
set -uo pipefail

echo "🔒 Firewall init..."

# ==========================================================================
# Detect iptables
# ==========================================================================
IPTABLES_CMD=""
if command -v iptables-nft &>/dev/null && iptables-nft -L -n &>/dev/null 2>&1; then
    IPTABLES_CMD="iptables-nft"
elif command -v iptables &>/dev/null && iptables -L -n &>/dev/null 2>&1; then
    IPTABLES_CMD="iptables"
else
    echo "⚠️  iptables unavailable (normal on Docker Desktop macOS/Windows)."
    echo "   Container VM provides isolation. Skipping network firewall."
    exit 0
fi

ipt() { $IPTABLES_CMD "$@"; }

# ==========================================================================
# Flush only the filter table. Leave nat and mangle ALONE.
# Docker's embedded DNS (127.0.0.11) depends on nat REDIRECT rules.
# Flushing nat kills DNS permanently inside the container.
# ==========================================================================
ipt -F
ipt -X

# ==========================================================================
# BASE RULES
# ==========================================================================

# Loopback
ipt -A INPUT  -i lo -j ACCEPT
ipt -A OUTPUT -o lo -j ACCEPT

# Established connections
ipt -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
ipt -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Docker embedded DNS at 127.0.0.11
ipt -A OUTPUT -d 127.0.0.11 -p udp --dport 53 -j ACCEPT
ipt -A OUTPUT -d 127.0.0.11 -p tcp --dport 53 -j ACCEPT
ipt -A INPUT  -s 127.0.0.11 -p udp --sport 53 -j ACCEPT
ipt -A INPUT  -s 127.0.0.11 -p tcp --sport 53 -j ACCEPT

# General DNS
ipt -A OUTPUT -p udp --dport 53 -j ACCEPT
ipt -A OUTPUT -p tcp --dport 53 -j ACCEPT

# SSH (git over SSH)
ipt -A OUTPUT -p tcp --dport 22 -j ACCEPT

# HTTPS + HTTP (Anthropic API, npm, PyPI, GitHub, CDNs, etc.)
ipt -A OUTPUT -p tcp --dport 443 -j ACCEPT
ipt -A OUTPUT -p tcp --dport 80 -j ACCEPT

# ==========================================================================
# HOST PORT ACCESS — supports ports and ranges: "5432,6379,8000:8100"
# ==========================================================================
HOST_IP=""
if getent hosts host.docker.internal &>/dev/null; then
    # getent may return IPv6 — iptables only handles IPv4, so filter for it
    HOST_IP=$(getent hosts host.docker.internal | awk '{print $1}' | grep -E '^[0-9]+\.' | head -1)
fi
if [ -z "$HOST_IP" ] && command -v ip &>/dev/null; then
    HOST_IP=$(ip route | grep default | awk '{print $3}' | head -1) || true
fi

DEFAULT_HOST_PORTS="3000,4000,8000,8080"
HOST_PORTS="${HOST_PORTS:-$DEFAULT_HOST_PORTS}"

if [ -n "$HOST_IP" ]; then
    echo "  Host: $HOST_IP"
    # Allow ICMP to host for diagnostics (ping)
    ipt -A OUTPUT -d "$HOST_IP" -p icmp -j ACCEPT 2>&1 || echo "  ⚠️  ICMP rule failed"
    IFS=',' read -ra PORTS <<< "$HOST_PORTS"
    for spec in "${PORTS[@]}"; do
        spec=$(echo "$spec" | tr -d '[:space:]')
        [ -z "$spec" ] && continue
        if ipt -A OUTPUT -d "$HOST_IP" -p tcp --dport "$spec" -j ACCEPT 2>&1; then
            [[ "$spec" == *":"* ]] && echo "  ✅ host:$spec (range)" || echo "  ✅ host:$spec"
        else
            echo "  ❌ host:$spec — iptables rule failed"
        fi
    done
else
    echo "  ⚠️  Could not resolve host IP — host port access will not work"
    echo "     Tried: getent hosts host.docker.internal, default gateway"
fi

# ==========================================================================
# DEFAULT DROP for everything else
# ==========================================================================
ipt -P INPUT DROP
ipt -P FORWARD DROP
ipt -P OUTPUT DROP

# ==========================================================================
# Validate
# ==========================================================================
echo ""
echo "  Validating..."

if dig +short +timeout=3 anthropic.com 2>/dev/null | grep -qE '^[0-9]'; then
    echo "  ✅ DNS working"
else
    echo "  ❌ DNS broken — flushing firewall"
    ipt -F; ipt -P INPUT ACCEPT; ipt -P OUTPUT ACCEPT; ipt -P FORWARD ACCEPT
    echo "  ⚠️  Firewall disabled. Container isolation still active."
    exit 0
fi

if curl -sf --max-time 8 -o /dev/null https://api.anthropic.com 2>/dev/null; then
    echo "  ✅ api.anthropic.com reachable"
else
    echo "  ⚠️  api.anthropic.com unreachable (may work once Claude resolves it)"
fi

if curl -sf --max-time 3 -o /dev/null http://example.com 2>/dev/null; then
    echo "  ⚠️  example.com reachable (HTTP/HTTPS open by design)"
else
    echo "  ✅ non-HTTP traffic blocked"
fi

# Validate host connectivity
if [ -n "$HOST_IP" ]; then
    echo ""
    echo "  Host connectivity ($HOST_IP):"
    IFS=',' read -ra PORTS <<< "$HOST_PORTS"
    for spec in "${PORTS[@]}"; do
        spec=$(echo "$spec" | tr -d '[:space:]')
        [ -z "$spec" ] && continue
        # For ranges, just test the first port
        test_port="${spec%%:*}"
        if curl -sf --max-time 2 --connect-timeout 2 -o /dev/null "http://$HOST_IP:$test_port" 2>/dev/null || \
           bash -c "echo >/dev/tcp/$HOST_IP/$test_port" 2>/dev/null; then
            echo "  ✅ host:$test_port reachable"
        else
            echo "  ⚠️  host:$test_port not reachable (service may not be running)"
        fi
    done
fi

echo ""
echo "🔒 Firewall ready."
echo "   Allowed: DNS, SSH, HTTP/HTTPS, host ports ($HOST_PORTS)"
echo "   Blocked: all other outbound (raw TCP, SMTP, etc.)"
