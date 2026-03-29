#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# VPN Stack Setup Script
# WireGuard (wg-easy) + Pi-hole + Caddy on Docker
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

get_env_value() {
    local key="$1"
    sed -n "s/^${key}=//p" .env | head -n 1
}

generate_wg_password_hash() {
    local password="$1"
    docker run --rm ghcr.io/wg-easy/wg-easy:14 node -e "const bcrypt = require('bcryptjs'); const hash = bcrypt.hashSync(process.argv[1], 10); console.log(hash.replace(/\\$/g, '$$$$'));" "$password"
}

# -----------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------
[[ $EUID -ne 0 ]] && err "Run this script as root: sudo bash setup.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------
# Gather configuration
# -----------------------------------------------------------
VPS_IP=$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')
log "Detected VPS IP: $VPS_IP"

if [[ -f .env ]]; then
    warn ".env already exists, loading it"
    WG_HOST="$(get_env_value WG_HOST)"
    WG_PASSWORD_HASH="$(get_env_value WG_PASSWORD_HASH)"
    LEGACY_WG_PASSWORD="$(get_env_value WG_PASSWORD)"
    PIHOLE_PASSWORD="$(get_env_value PIHOLE_PASSWORD)"
    TZ="$(get_env_value TZ)"

    if [[ -z "$WG_PASSWORD_HASH" && -n "$LEGACY_WG_PASSWORD" ]]; then
        warn "Migrating legacy WG_PASSWORD to WG_PASSWORD_HASH"
        WG_PASSWORD_HASH="$(generate_wg_password_hash "$LEGACY_WG_PASSWORD")"
        cat > .env <<EOF
WG_HOST=$WG_HOST
WG_PASSWORD_HASH=$WG_PASSWORD_HASH
PIHOLE_PASSWORD=$PIHOLE_PASSWORD
TZ=$TZ
EOF
        log "Updated .env to use WG_PASSWORD_HASH"
    fi
else
    read -rp "VPS public IP [$VPS_IP]: " input_ip
    WG_HOST="${input_ip:-$VPS_IP}"

    read -rp "WireGuard UI password: " WG_PASSWORD
    [[ -z "$WG_PASSWORD" ]] && err "Password cannot be empty"

    read -rp "Pi-hole UI password: " PIHOLE_PASSWORD
    [[ -z "$PIHOLE_PASSWORD" ]] && err "Password cannot be empty"

    read -rp "Timezone [America/New_York]: " input_tz
    TZ="${input_tz:-America/New_York}"

    if ! command -v docker &>/dev/null; then
        log "Installing Docker..."
        apt update -qq && apt upgrade -y -qq
        apt install -y -qq docker.io docker-compose-v2
        systemctl enable --now docker
    fi

    WG_PASSWORD_HASH="$(generate_wg_password_hash "$WG_PASSWORD")"

    cat > .env <<EOF
WG_HOST=$WG_HOST
WG_PASSWORD_HASH=$WG_PASSWORD_HASH
PIHOLE_PASSWORD=$PIHOLE_PASSWORD
TZ=$TZ
EOF
    log "Created .env file"
fi

# -----------------------------------------------------------
# Step 1: System update & Docker install
# -----------------------------------------------------------
log "Updating system packages..."
apt update -qq && apt upgrade -y -qq

if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    apt install -y -qq docker.io docker-compose-v2
    systemctl enable --now docker
else
    log "Docker already installed"
fi

# -----------------------------------------------------------
# Step 2: Free port 53 (disable systemd-resolved)
# -----------------------------------------------------------
if systemctl is-active --quiet systemd-resolved; then
    log "Stopping systemd-resolved to free port 53..."
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
    log "Port 53 freed"
else
    log "systemd-resolved already stopped"
fi

# -----------------------------------------------------------
# Step 3: Enable IP forwarding
# -----------------------------------------------------------
log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# -----------------------------------------------------------
# Step 4: Create directory structure
# -----------------------------------------------------------
log "Creating directory structure..."
mkdir -p wireguard pihole/etc-pihole pihole/etc-dnsmasq.d caddy

# -----------------------------------------------------------
# Step 5: Stop and clean existing containers
# -----------------------------------------------------------
if docker compose ps -q 2>/dev/null | grep -q .; then
    warn "Stopping existing containers..."
    docker compose down --remove-orphans
fi

# Remove old data if requested
if [[ "${CLEAN_INSTALL:-}" == "true" ]]; then
    warn "Clean install: removing all existing data..."
    rm -rf wireguard/* pihole/etc-pihole/* pihole/etc-dnsmasq.d/*
fi

# -----------------------------------------------------------
# Step 6: Deploy the stack
# -----------------------------------------------------------
log "Pulling latest images..."
docker compose pull

log "Starting services..."
docker compose up -d

# -----------------------------------------------------------
# Step 7: Wait for services to be ready
# -----------------------------------------------------------
log "Waiting for services to start..."
sleep 10

# Wait for Pi-hole to be healthy (max 60s)
log "Waiting for Pi-hole to be ready..."
for i in $(seq 1 12); do
    if docker exec pihole dig @127.0.0.1 google.com +short +timeout=2 &>/dev/null; then
        log "Pi-hole is responding to DNS queries"
        break
    fi
    if [[ $i -eq 12 ]]; then
        warn "Pi-hole may still be initializing. Check logs: docker logs pihole"
    fi
    sleep 5
done

# -----------------------------------------------------------
# Step 8: Verify services
# -----------------------------------------------------------
echo ""
log "========================================="
log "  Stack deployed successfully!"
log "========================================="
echo ""
echo "  Services:"
echo "    WireGuard VPN:  UDP port 51820"
echo "    VPN Panel:      https://vpn.workingpos.com"
echo "    DNS Panel:      https://dns.workingpos.com/admin"
echo ""
echo "  DNS test from VPS:"

if dig @172.20.0.3 google.com +short +timeout=3 2>/dev/null | head -1; then
    echo "    Pi-hole DNS: OK"
else
    echo "    Pi-hole DNS: NOT READY (check: docker logs pihole)"
fi

echo ""
echo "  Next steps:"
echo "    1. Open https://vpn.workingpos.com and create VPN clients"
echo "    2. Open https://dns.workingpos.com/admin to manage Pi-hole"
echo "    3. Connect your devices using the WireGuard app"
echo ""
warn "Make sure DNS records for vpn.workingpos.com and dns.workingpos.com"
warn "point to $WG_HOST before Caddy can issue SSL certificates."
echo ""
