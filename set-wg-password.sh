#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[x]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && err "Run this script as root: sudo bash set-wg-password.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

command -v docker >/dev/null 2>&1 || err "Docker is required"

read -rp "New WireGuard UI password: " WG_PASSWORD
[[ -z "$WG_PASSWORD" ]] && err "Password cannot be empty"

WG_PASSWORD_HASH="$(docker run --rm ghcr.io/wg-easy/wg-easy:14 node -e 'const bcrypt = require("bcryptjs"); const hash = bcrypt.hashSync(process.argv[1], 10); console.log(hash.replace(/\$/g, "$$$$"));' "$WG_PASSWORD")"

if [[ -f .env ]]; then
    sed -i '/^WG_PASSWORD_HASH=/d' .env
else
    touch .env
fi

printf 'WG_PASSWORD_HASH=%s\n' "$WG_PASSWORD_HASH" >> .env
log "Updated .env"

if docker compose ps -q wg-easy >/dev/null 2>&1 && [[ -n "$(docker compose ps -q wg-easy 2>/dev/null)" ]]; then
    docker compose up -d wg-easy
    log "Restarted wg-easy"
elif docker compose -f docker-compose.traefik.yml ps -q wg-easy >/dev/null 2>&1 && [[ -n "$(docker compose -f docker-compose.traefik.yml ps -q wg-easy 2>/dev/null)" ]]; then
    docker compose -f docker-compose.traefik.yml up -d wg-easy
    log "Restarted wg-easy (Traefik mode)"
else
    log "Password saved. Start or restart your stack to apply it."
fi
