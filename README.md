# ts-zapret-wg: Tailscale Exit Node + zapret DPI Bypass + WireGuard Routing

All-in-one Docker gateway that provides:
- **Tailscale exit node** for your devices
- **zapret DPI bypass** for censorship circumvention
- **Conditional WireGuard routing** for specific domains (DMM, Cygames, etc.)

## 💡 Why This Project?

Tired of constantly switching VPNs for different use cases? This project solves that problem.

**The Problem:**
- You use Tailscale all the time
- Some services require a different VPN location (e.g., geo-restricted content)
- Some websites are blocked by government and need DPI bypass

**The Solution:**
This gateway routes different traffic through different paths while keeping your Tailscale always on:
- **Specific domains** → WireGuard (custom VPN location)
- **Blocked websites** → zapret (DPI bypass)
- **Everything else** → Normal connection through your Tailscale Exit Node
## 📋 Architecture

```
Tailscale Client → tailscale0
                       ↓
               iptables rules
          ┌────────┴────────┐
          ↓                 ↓
     Port 80/443      dst ∈ vpn_domains
          ↓                 ↓
    zapret (DPI)       WireGuard (VPN)
          ↓                 ↓
     Normal WAN        VPN Exit
```

## 🚀 Quick Start

### 1. Clone & Configure

```bash
git clone https://github.com/CVHNupsXD/dmm-wg-routing.git
cd dmm-wg-routing

# Copy and edit config files
cp .env.example .env
cp config/wg0.conf.example config/wg0.conf

# Edit .env with your credentials
nano .env

# Edit WireGuard config with your JP VPN details
nano config/wg0.conf
```

### 2. Environment Variables

Edit `.env`:

```bash
# Tailscale auth key (https://login.tailscale.com/admin/settings/keys)
TS_AUTHKEY=tskey-auth-xxxxx

# AdGuard Home API (optional, for DNS rewrites)
AGH_URL=http://127.0.0.1:3000
AGH_USER=admin
AGH_PASS=your_password

# Domain resolution interval (seconds, default: 43200 = 12 hours)
RESOLVE_INTERVAL=43200
```

### 3. WireGuard Config

Edit `config/wg0.conf` with your VPN provider details:

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.0.0.2/32

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### 4. Build & Run

```bash
docker compose up -d --build
```

### 5. Verify

```bash
# Check container logs
docker logs -f ts-zapret-wg

# Check Tailscale status
docker exec ts-zapret-wg tailscale status

# Check ipset
docker exec ts-zapret-wg ipset list vpn_domains
```

## 📁 File Structure

```
ts-zapret-wg/
├── docker/
│   └── Dockerfile
├── docker-compose.yml
├── scripts/
│   ├── entrypoint.sh              # Startup orchestration
│   ├── setup-iptables.sh          # iptables rules
│   ├── resolve-domains-local.sh   # Local DoH domain resolver
│   └── update-vpn-ipset.sh        # Update ipset + AdGuard sync
├── config/
│   ├── wg0.conf.example           # WireGuard template
│   ├── domains.txt                # Domains to resolve
│   └── zapret-hosts-user.txt      # Zapret hostlist
└── .env.example                   # Environment variables template
```

## 🔧 How It Works

### Domain Resolution
- Container resolves domains from `domains.txt` at startup
- Uses Japan-based DoH (IIJ) for geo-correct IPs via `dog` DNS tool
- Re-resolves every 12 hours by default (configurable via `RESOLVE_INTERVAL`)
- Updates ipset and AdGuard Home DNS rewrites automatically

### Container Startup
1. **IP forwarding** enabled
2. **ipset** set created (`vpn_domains`)
3. **WireGuard** started with VPN config
4. **Policy routing** configured (mark 0x1 → wg0)
5. **iptables** rules applied
6. **zapret** started for DPI bypass
7. **Tailscale** started as exit node
8. **Initial domain resolution** performed
9. **Resolver loop** starts (re-resolves every 12h by default)

### Traffic Routing
| Destination | Action |
|-------------|--------|
| Port 80, 443 | → zapret → Normal WAN |
| ∈ `vpn_domains` | → Mark 0x1 → WireGuard → JP VPN |
| Everything else | → Normal WAN |

## 🔍 Debugging

```bash
# Container shell
docker exec -it ts-zapret-wg bash

# Check iptables
iptables -t mangle -L GATEWAY_PREROUTE -v -n
iptables -t nat -L GATEWAY_POSTROUTE -v -n

# Check WireGuard
wg show

# Check Tailscale
tailscale status

# Check ipset
ipset list vpn_domains

# Test IP routing
ip route get xxx.xx.xx.xxx
```

Add more domains to `config/domains.txt` and restart the container to include them.
