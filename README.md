# 🛡️ VPN Stack

> 🔒 A self-hosted VPN stack running on Docker — encrypted tunneling, ad blocking, and automatic HTTPS in one deploy.

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![WireGuard](https://img.shields.io/badge/WireGuard-VPN-88171A?logo=wireguard&logoColor=white)](https://www.wireguard.com/)
[![Pi-hole](https://img.shields.io/badge/Pi--hole-DNS-96060C?logo=pihole&logoColor=white)](https://pi-hole.net/)
[![Caddy](https://img.shields.io/badge/Caddy-HTTPS-1F88C0?logo=caddy&logoColor=white)](https://caddyserver.com/)

---

## 🏗️ Architecture

```
🖥️ Client Device                        ☁️  VPS (Docker)
+--------------+                     +---------------------------+
|  WireGuard   | ──── UDP:51820 ───> |  🔐 wg-easy (WireGuard)   |
|  App         |                     |    │                      |
|              |  DNS queries ─────> |  🚫 Pi-hole (ad blocking) |
|              |                     |    │                      |
|              |  HTTPS panels ────> |  🌐 Caddy (reverse proxy) |
+--------------+                     +---------------------------+
```

## 📦 What's Included

| Service | Purpose | Access |
|:--------|:--------|:-------|
| 🔐 [wg-easy](https://github.com/wg-easy/wg-easy) | WireGuard VPN with web UI for client management | `vpn.yourdomain.com` |
| 🚫 [Pi-hole](https://pi-hole.net/) | DNS-level ad and tracker blocking | `dns.yourdomain.com/admin` |
| 🌐 [Caddy](https://caddyserver.com/) | Reverse proxy with automatic Let's Encrypt TLS | Ports 80/443 |

## 📋 Requirements

- 🖥️ A VPS with a public IP (tested on Ubuntu 24.04)
- 🌍 Two DNS `A` records pointing to your VPS IP
- 🔓 Ports open: `51820/udp`, `80/tcp`, `443/tcp`

## ⚡ Quick Start

```bash
git clone https://github.com/cswni/vpn-stack.git
cd vpn-stack
sudo bash setup.sh
```

The setup script handles everything interactively:

1. 📝 Prompts for your VPS IP, passwords, and timezone
2. 📦 Installs Docker if needed
3. 🔌 Frees port 53 (disables `systemd-resolved`)
4. 🐳 Pulls images and starts the stack
5. ✅ Verifies all services are running

## 🔧 Manual Setup

If you prefer to configure things yourself:

**1️⃣ Create your environment file:**

```bash
cp .env.example .env
nano .env
```

**2️⃣ Update `caddy/Caddyfile` with your domains.**

**3️⃣ Free port 53 and deploy:**

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf

sudo docker compose up -d
```

## ⚙️ Configuration

### 🔑 Environment Variables

| Variable | Description |
|:---------|:------------|
| `WG_HOST` | 🌐 VPS public IP address |
| `WG_PASSWORD_HASH` | 🔐 bcrypt password hash for the WireGuard web UI |
| `PIHOLE_PASSWORD` | 🚫 Password for the Pi-hole admin panel |
| `TZ` | 🕐 Timezone (e.g. `America/New_York`) |

### 🌐 Network Layout

```
📡 172.20.0.0/24  (vpn_net)
   ├── .2  🔐 wg-easy
   └── .3  🚫 pihole
```

WireGuard clients receive IPs in the `10.8.0.0/24` range. DNS queries from VPN clients are routed to Pi-hole at `172.20.0.3`.

### 📄 Caddyfile

Edit `caddy/Caddyfile` to match your domains:

```caddy
vpn.yourdomain.com {
    reverse_proxy wg-easy:51821
}

dns.yourdomain.com {
    reverse_proxy pihole:80
}
```

> 💡 Caddy automatically obtains and renews TLS certificates from Let's Encrypt. No extra config needed.

## 📱 Adding VPN Clients

1. 🌐 Open `https://vpn.yourdomain.com`
2. 🔑 Log in with the plain-text password you entered during `setup.sh`

Generate a hash manually if you are creating `.env` yourself:

```bash
docker run --rm ghcr.io/wg-easy/wg-easy:14 node -e 'const bcrypt = require("bcryptjs"); const hash = bcrypt.hashSync("YOUR_PASSWORD", 10); console.log(hash.replace(/\$/g, "$$$$"));'
```

Then put the output in `WG_PASSWORD_HASH`.
3. ➕ Click **New Client** and give it a name
4. 📷 Scan the QR code with the WireGuard app on your phone, or download the `.conf` file for desktop

> 🍎 **iOS / Android:** Download [WireGuard](https://www.wireguard.com/install/) from the App Store or Play Store  
> 🖥️ **Windows / macOS / Linux:** Download the desktop client from [wireguard.com/install](https://www.wireguard.com/install/)

## 📁 File Structure

```
vpn-stack/
├── 📄 .env.example          # Template for environment variables
├── 📄 .gitignore             # Keeps secrets and data out of git
├── 🐳 docker-compose.yml     # Service definitions
├── 🚀 setup.sh               # Automated setup script
├── 📂 caddy/
│   └── 📄 Caddyfile          # Reverse proxy configuration
└── 📂 docs/                  # GitHub Pages documentation
    └── 📄 index.html
```

## 🔍 Troubleshooting

<details>
<summary>🚫 Pi-hole not blocking ads</summary>

Verify the listening mode is set to accept queries from VPN clients:

```bash
docker exec pihole grep listeningMode /etc/pihole/pihole.toml
# Should show: listeningMode = "ALL"
```

If it shows `LOCAL`, the stack was not deployed with the correct environment variables. Recreate Pi-hole:

```bash
docker compose down pihole
rm -f pihole/etc-pihole/pihole.toml
docker compose up -d pihole
```

</details>

<details>
<summary>🌐 DNS not resolving through VPN</summary>

Check that Pi-hole can reach upstream DNS:

```bash
docker exec pihole dig @127.0.0.1 google.com +short
```

If this times out, check upstream DNS configuration:

```bash
docker exec pihole grep -A4 "upstreams" /etc/pihole/pihole.toml
```

</details>

<details>
<summary>🔒 Caddy not issuing certificates</summary>

Make sure your DNS A records point to the VPS IP and ports 80/443 are open:

```bash
dig vpn.yourdomain.com +short
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

</details>

<details>
<summary>📋 Check service logs</summary>

```bash
docker logs wg-easy    # VPN logs
docker logs pihole     # DNS logs
docker logs caddy      # Proxy logs
```

</details>

## 📖 Documentation

Full documentation is available at **[cswni.github.io/vpn-stack](https://cswni.github.io/vpn-stack)**

## 📜 License

MIT — use it, fork it, deploy it. 🚀
