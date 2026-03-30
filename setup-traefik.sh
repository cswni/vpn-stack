#!/usr/bin/env bash
set -euo pipefail

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
    docker run --rm ghcr.io/wg-easy/wg-easy:14 node -e 'const bcrypt = require("bcryptjs"); const hash = bcrypt.hashSync(process.argv[1], 10); console.log(hash.replace(/\$/g, "$$$$"));' "$password"
}

[[ $EUID -ne 0 ]] && err "Run this script as root: sudo bash setup-traefik.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

command -v docker >/dev/null 2>&1 || err "Docker is required and must already be installed"
docker compose version >/dev/null 2>&1 || err "docker compose plugin is required"

VPS_IP=$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')
log "Detected VPS IP: $VPS_IP"

if [[ -f .env ]]; then
    warn ".env already exists, reusing it"
else
    read -rp "VPS public IP [$VPS_IP]: " input_ip
    WG_HOST="${input_ip:-$VPS_IP}"

    read -rp "WireGuard UI password: " WG_PASSWORD
    [[ -z "$WG_PASSWORD" ]] && err "Password cannot be empty"

    read -rp "Pi-hole UI password: " PIHOLE_PASSWORD
    [[ -z "$PIHOLE_PASSWORD" ]] && err "Password cannot be empty"

    read -rp "Timezone [America/New_York]: " input_tz
    TZ="${input_tz:-America/New_York}"

    read -rp "VPN panel domain [vpn.workingpos.com]: " input_vpn_domain
    VPN_DOMAIN="${input_vpn_domain:-vpn.workingpos.com}"

    read -rp "Pi-hole domain [dns.workingpos.com]: " input_dns_domain
    DNS_DOMAIN="${input_dns_domain:-dns.workingpos.com}"

    read -rp "Traefik docker network [traefik-net]: " input_traefik_network
    TRAEFIK_DOCKER_NETWORK="${input_traefik_network:-traefik-net}"

    read -rp "Traefik constraint label [traefik-net]: " input_constraint
    TRAEFIK_CONSTRAINT_LABEL="${input_constraint:-traefik-net}"

    read -rp "Traefik entrypoint [https]: " input_entrypoint
    TRAEFIK_ENTRYPOINT="${input_entrypoint:-https}"

    read -rp "Traefik certresolver [le]: " input_certresolver
    TRAEFIK_CERTRESOLVER="${input_certresolver:-le}"

    WG_PASSWORD_HASH="$(generate_wg_password_hash "$WG_PASSWORD")"

    cat > .env <<EOF
WG_HOST=$WG_HOST
WG_PASSWORD_HASH=$WG_PASSWORD_HASH
PIHOLE_PASSWORD=$PIHOLE_PASSWORD
TZ=$TZ
VPN_DOMAIN=$VPN_DOMAIN
DNS_DOMAIN=$DNS_DOMAIN
TRAEFIK_DOCKER_NETWORK=$TRAEFIK_DOCKER_NETWORK
TRAEFIK_CONSTRAINT_LABEL=$TRAEFIK_CONSTRAINT_LABEL
TRAEFIK_ENTRYPOINT=$TRAEFIK_ENTRYPOINT
TRAEFIK_CERTRESOLVER=$TRAEFIK_CERTRESOLVER
EOF
    log "Created .env file"
fi

if systemctl is-active --quiet systemd-resolved; then
    log "Stopping systemd-resolved to free port 53..."
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
    log "Port 53 freed"
else
    log "systemd-resolved already stopped"
fi

log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

log "Creating directory structure..."
mkdir -p wireguard pihole/etc-pihole pihole/etc-dnsmasq.d

TRAEFIK_DOCKER_NETWORK="$(get_env_value TRAEFIK_DOCKER_NETWORK)"
docker network inspect "$TRAEFIK_DOCKER_NETWORK" >/dev/null 2>&1 || err "Docker network '$TRAEFIK_DOCKER_NETWORK' does not exist"

if docker compose -f docker-compose.traefik.yml ps -q 2>/dev/null | grep -q .; then
    warn "Stopping existing Traefik-mode containers..."
    docker compose -f docker-compose.traefik.yml down --remove-orphans
fi

log "Pulling latest images..."
docker compose -f docker-compose.traefik.yml pull

log "Starting services..."
docker compose -f docker-compose.traefik.yml up -d

sleep 10

echo ""
log "========================================="
log "  Traefik-mode stack deployed successfully!"
log "========================================="
echo ""
echo "  Services:"
echo "    WireGuard VPN:  UDP port 51820"
echo "    VPN Panel:      https://$(get_env_value VPN_DOMAIN)"
echo "    DNS Panel:      https://$(get_env_value DNS_DOMAIN)/admin"
echo ""
warn "Make sure Traefik is attached to network '$(get_env_value TRAEFIK_DOCKER_NETWORK)'"
warn "and your DNS records point to $(get_env_value WG_HOST)."
