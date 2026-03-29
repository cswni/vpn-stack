# VPN Stack

A self-hosted VPN stack running on Docker. Combines WireGuard for encrypted tunneling, Pi-hole for network-wide ad blocking, and Caddy for automatic HTTPS on management panels.

```
Client Device                        VPS (Docker)
+--------------+                     +---------------------------+
|  WireGuard   | --- UDP:51820 ----> |  wg-easy (WireGuard)      |
|  App         |                     |    |                      |
|              |  DNS queries -----> |  Pi-hole (ad blocking)    |
|              |                     |    |                      |
|              |  HTTPS panels ----> |  Caddy (reverse proxy)    |
+--------------+                     +---------------------------+
```

## What's Included

| Service | Purpose | Access |
|---------|---------|--------|
| [wg-easy](https://github.com/wg-easy/wg-easy) | WireGuard VPN with web UI for client management | `vpn.yourdomain.com` |
| [Pi-hole](https://pi-hole.net/) | DNS-level ad and tracker blocking | `dns.yourdomain.com/admin` |
| [Caddy](https://caddyserver.com/) | Reverse proxy with automatic Let's Encrypt TLS | Ports 80/443 |

## Requirements

- A VPS with a public IP (tested on Ubuntu 24.04)
- Two DNS A records pointing to your VPS IP
- Ports open: `51820/udp`, `80/tcp`, `443/tcp`

## Quick Start

```bash
git clone https://github.com/cswni/vpn-stack.git
cd vpn-stack
sudo bash setup.sh
```

The script will prompt for your VPS IP, passwords, and timezone. It handles everything else: Docker installation, freeing port 53, pulling images, and starting the stack.

## Manual Setup

If you prefer to configure things yourself:

1. Copy the example environment file and edit it:

```bash
cp .env.example .env
nano .env
```

2. Update `caddy/Caddyfile` with your domains.

3. Free port 53 and deploy:

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf

sudo docker compose up -d
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `WG_HOST` | VPS public IP address |
| `WG_PASSWORD` | Password for the WireGuard web UI |
| `PIHOLE_PASSWORD` | Password for the Pi-hole admin panel |
| `TZ` | Timezone (e.g. `America/New_York`) |

### Network Layout

```
172.20.0.0/24  (vpn_net)
  .2  wg-easy
  .3  pihole
```

WireGuard clients receive IPs in the `10.8.0.0/24` range. DNS queries from VPN clients are routed to Pi-hole at `172.20.0.3`.

### Caddyfile

Edit `caddy/Caddyfile` to match your domains:

```caddy
vpn.yourdomain.com {
    reverse_proxy wg-easy:51821
}

dns.yourdomain.com {
    reverse_proxy pihole:80
}
```

Caddy automatically obtains and renews TLS certificates from Let's Encrypt.

## Adding VPN Clients

1. Open `https://vpn.yourdomain.com`
2. Log in with the password you set in `WG_PASSWORD`
3. Click **New Client**, give it a name
4. Scan the QR code with the WireGuard app on your phone, or download the `.conf` file for desktop

## File Structure

```
vpn-stack/
  .env.example        # Template for environment variables
  .gitignore           # Keeps secrets and data out of git
  docker-compose.yml   # Service definitions
  setup.sh             # Automated setup script
  caddy/
    Caddyfile           # Reverse proxy configuration
```

## Troubleshooting

**Pi-hole not blocking ads**

Verify the listening mode is set to accept queries from VPN clients:

```bash
docker exec pihole grep listeningMode /etc/pihole/pihole.toml
# Should show: listeningMode = "ALL"
```

**DNS not resolving through VPN**

Check that Pi-hole can reach upstream DNS:

```bash
docker exec pihole dig @127.0.0.1 google.com +short
```

**Caddy not issuing certificates**

Make sure your DNS A records point to the VPS IP and ports 80/443 are open:

```bash
dig vpn.yourdomain.com +short
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**Check service logs**

```bash
docker logs wg-easy
docker logs pihole
docker logs caddy
```

## License

MIT
