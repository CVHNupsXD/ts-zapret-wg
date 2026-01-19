#!/bin/bash

set -e

echo "=== Gateway Container Starting ==="

echo "Enabling IP forwarding and configuring RP Filter..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv4.conf.all.rp_filter=2
sysctl -w net.ipv4.conf.default.rp_filter=2
for iface in /proc/sys/net/ipv4/conf/*; do
    echo 2 > "$iface/rp_filter" 2>/dev/null || true
done

echo "Creating ipset sets..."
ipset create vpn_domains hash:ip timeout 3600 -exist
ipset create vpn_domains hash:ip timeout 3600 -exist

if [[ -f "$WG_CONFIG" ]]; then
    echo "Starting WireGuard..."
    
    mkdir -p /etc/wireguard
    
    cp "$WG_CONFIG" /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf
    
    wg-quick down wg0 2>/dev/null || true
    sleep 1
    
    wg-quick up wg0
    
    ip route flush table 51820 2>/dev/null || true
    
    ip link set wg0 mtu 1280 || true
    
    echo "WireGuard interface up (MTU 1280)"
    wg show wg0
else
    echo "WARNING: WireGuard config not found at $WG_CONFIG"
fi

echo "Setting up policy routing (Table 100)..."
ip route del default dev wg0 table 100 2>/dev/null || true
ip rule del fwmark 0x1 table 100 2>/dev/null || true

ip route add default dev wg0 table 100
ip rule add fwmark 0x1 table 100 priority 100

while ip rule del table 51820 2>/dev/null; do :; done
while ip rule del from all lookup main suppress_prefixlength 0 2>/dev/null; do :; done

ip route add default dev wg0 table 100 2>/dev/null || true
ip rule add fwmark 0x1 table 100 2>/dev/null || 

echo "Starting zapret..."
pkill -f nfqws 2>/dev/null || true
sleep 1

ZAPRET_HOSTS="/config/zapret-hosts-user.txt"
if [[ -f "$ZAPRET_HOSTS" ]]; then
    nfqws --daemon --pidfile=/var/run/nfqws.pid --uid=0 \
        --dpi-desync=fake,split2 \
        --dpi-desync-ttl=2 \
        --dpi-desync-fooling=md5sig \
        --hostlist="$ZAPRET_HOSTS" \
        --qnum=200 || echo "zapret failed to start"
else
    echo "WARNING: $ZAPRET_HOSTS not found, zapret running without hostlist"
    nfqws --daemon --pidfile=/var/run/nfqws.pid --uid=0 \
        --dpi-desync=fake,split2 \
        --dpi-desync-ttl=2 \
        --dpi-desync-fooling=md5sig \
        --qnum=200 || echo "zapret failed to start"
fi

echo "Starting Tailscale..."
pkill -f tailscaled 2>/dev/null || true
sleep 1

tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
sleep 3

if [[ -n "$TS_AUTHKEY" ]]; then
    tailscale up --reset --authkey="$TS_AUTHKEY" --advertise-exit-node --accept-dns=false
else
    echo "WARNING: No TS_AUTHKEY provided. Run 'tailscale up' manually."
    tailscale up --reset --advertise-exit-node --accept-dns=false || true
fi

sleep 7

# Why u have to do this tailscale ?
WAN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
LOCAL_NET=$(ip -o -f inet addr show "$WAN_IFACE" | awk '{print $4}')

if [[ -n "$LOCAL_NET" ]] && [[ -n "$WAN_IFACE" ]]; then
    echo "Adding rule to bypass Tailscale for local network $LOCAL_NET"
    ip rule del to "$LOCAL_NET" table main priority 50 2>/dev/null || true
    ip rule add to "$LOCAL_NET" table main priority 50
fi

echo "Configuring iptables..."
/scripts/setup-iptables.sh

echo "Resolving domains locally using DoH..."
if [[ -f "/scripts/resolve-domains-local.sh" ]]; then
    /scripts/resolve-domains-local.sh
    if [[ -f "/tmp/ips.txt" ]]; then
        echo "Domain resolution successful, updating ipset..."
        /scripts/update-vpn-ipset.sh
    else
        echo "WARNING: Domain resolution failed, skipping ipset update"
    fi
else
    echo "WARNING: resolve-domains-local.sh not found, skipping domain resolution"
fi

echo "Starting resolver loop (interval: ${RESOLVE_INTERVAL:-43200}s)..."
while true; do
    sleep "${RESOLVE_INTERVAL:-43200}"
    echo "Re-resolving domains..."
    /scripts/resolve-domains-local.sh && /scripts/update-vpn-ipset.sh
done &

echo "=== Gateway Ready ==="

wait