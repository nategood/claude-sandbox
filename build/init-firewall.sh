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
HOST_IPS=()

# /etc/hosts is the most reliable source on Docker Desktop (extra_hosts: host-gateway)
if grep -q host.docker.internal /etc/hosts 2>/dev/null; then
    while IFS= read -r ip; do
        HOST_IPS+=("$ip")
    done < <(grep host.docker.internal /etc/hosts | awk '{print $1}' | grep -E '^[0-9]+\.')
fi

# Fallback: getent (may return IPv6, so filter)
if [ ${#HOST_IPS[@]} -eq 0 ] && getent hosts host.docker.internal &>/dev/null; then
    while IFS= read -r ip; do
        HOST_IPS+=("$ip")
    done < <(getent hosts host.docker.internal | awk '{print $1}' | grep -E '^[0-9]+\.')
fi

# Also add default gateway if it's a different IP (bridge network)
if command -v ip &>/dev/null; then
    gw=$(ip route | grep default | awk '{print $3}' | head -1) || true
    if [ -n "$gw" ]; then
        already=false
        for existing in "${HOST_IPS[@]}"; do
            [ "$existing" = "$gw" ] && already=true
        done
        $already || HOST_IPS+=("$gw")
    fi
fi

DEFAULT_HOST_PORTS="3000,4000,8000,8080"
HOST_PORTS="${HOST_PORTS:-$DEFAULT_HOST_PORTS}"

if [ ${#HOST_IPS[@]} -gt 0 ]; then
    echo "  Host IPs: ${HOST_IPS[*]}"
    for HOST_IP in "${HOST_IPS[@]}"; do
        ipt -A OUTPUT -d "$HOST_IP" -p icmp -j ACCEPT 2>&1 || echo "  ⚠️  ICMP rule failed for $HOST_IP"
        IFS=',' read -ra PORTS <<< "$HOST_PORTS"
        for spec in "${PORTS[@]}"; do
            spec=$(echo "$spec" | tr -d '[:space:]')
            [ -z "$spec" ] && continue
            if ipt -A OUTPUT -d "$HOST_IP" -p tcp --dport "$spec" -j ACCEPT 2>&1; then
                [[ "$spec" == *":"* ]] && echo "  ✅ $HOST_IP:$spec (range)" || echo "  ✅ $HOST_IP:$spec"
            else
                echo "  ❌ $HOST_IP:$spec — iptables rule failed"
            fi
        done
    done
else
    echo "  ⚠️  Could not resolve host IP — host port access will not work"
    echo "     Tried: /etc/hosts, getent, default gateway"
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

# Validate host connectivity (test against first IP only)
if [ ${#HOST_IPS[@]} -gt 0 ]; then
    TEST_IP="${HOST_IPS[0]}"
    echo ""
    echo "  Host connectivity ($TEST_IP):"
    IFS=',' read -ra PORTS <<< "$HOST_PORTS"
    for spec in "${PORTS[@]}"; do
        spec=$(echo "$spec" | tr -d '[:space:]')
        [ -z "$spec" ] && continue
        test_port="${spec%%:*}"
        if curl -sf --max-time 2 --connect-timeout 2 -o /dev/null "http://$TEST_IP:$test_port" 2>/dev/null || \
           bash -c "echo >/dev/tcp/$TEST_IP/$test_port" 2>/dev/null; then
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
