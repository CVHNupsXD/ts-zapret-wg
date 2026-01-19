#!/bin/bash

#
# iptables rules for host network stack
#

set -e

echo "Setting up iptables rules..."

WAN_IFACE=""
for iface in eth0 enp0s3 end0 ens3; do
    if ip link show "$iface" &>/dev/null; then
        WAN_IFACE="$iface"
        break
    fi
done

if [[ -z "$WAN_IFACE" ]]; then
    echo "WARNING: Could not detect WAN interface, using eth0"
    WAN_IFACE="eth0"
fi

echo "WAN interface: $WAN_IFACE"

LOCAL_NET=$(ip -o -f inet addr show "$WAN_IFACE" | awk '{print $4}')
echo "Local network: $LOCAL_NET"

iptables -t mangle -D PREROUTING -j GATEWAY_PREROUTE 2>/dev/null || true
iptables -t mangle -D OUTPUT -j GATEWAY_OUTPUT 2>/dev/null || true
iptables -t nat -D POSTROUTING -j GATEWAY_POSTROUTE 2>/dev/null || true
iptables -D FORWARD -j GATEWAY_FORWARD 2>/dev/null || true

iptables -t mangle -F GATEWAY_PREROUTE 2>/dev/null || true
iptables -t mangle -X GATEWAY_PREROUTE 2>/dev/null || true
iptables -t mangle -F GATEWAY_OUTPUT 2>/dev/null || true
iptables -t mangle -X GATEWAY_OUTPUT 2>/dev/null || true
iptables -t nat -F GATEWAY_POSTROUTE 2>/dev/null || true
iptables -t nat -X GATEWAY_POSTROUTE 2>/dev/null || true
iptables -F GATEWAY_FORWARD 2>/dev/null || true
iptables -X GATEWAY_FORWARD 2>/dev/null || true

iptables -D FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
iptables -D FORWARD -o tailscale0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true

iptables -D FORWARD -s "$LOCAL_NET" -d "$LOCAL_NET" -j ACCEPT 2>/dev/null || true

iptables -t mangle -N GATEWAY_PREROUTE
iptables -t mangle -N GATEWAY_OUTPUT
iptables -t nat -N GATEWAY_POSTROUTE
iptables -N GATEWAY_FORWARD

iptables -I FORWARD 1 -s "$LOCAL_NET" -d "$LOCAL_NET" -j ACCEPT

iptables -I FORWARD 2 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -I FORWARD 3 -j GATEWAY_FORWARD

iptables -t mangle -I PREROUTING 1 -j GATEWAY_PREROUTE
iptables -t mangle -I OUTPUT 1 -j GATEWAY_OUTPUT
iptables -t nat -I POSTROUTING 1 -j GATEWAY_POSTROUTE

iptables -A GATEWAY_FORWARD -i "$WAN_IFACE" -o tailscale0 -j ACCEPT
iptables -A GATEWAY_FORWARD -i wg0 -o tailscale0 -j ACCEPT

iptables -A GATEWAY_FORWARD -i tailscale0 -o "$WAN_IFACE" -j ACCEPT
iptables -A GATEWAY_FORWARD -i tailscale0 -o wg0 -j ACCEPT

iptables -A GATEWAY_FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -t mangle -A GATEWAY_PREROUTE \
    -j CONNMARK --restore-mark --nfmask 0x1 --ctmask 0x1

iptables -t mangle -A GATEWAY_PREROUTE \
    -i tailscale0 \
    -m set --match-set vpn_domains dst \
    -j MARK --set-mark 0x1

iptables -t mangle -A GATEWAY_PREROUTE \
    -i tailscale0 \
    -p tcp -m multiport --dports 80,443 \
    -j NFQUEUE --queue-num 200 --queue-bypass

iptables -t mangle -A GATEWAY_PREROUTE \
    -m mark --mark 0x1 \
    -j CONNMARK --save-mark --nfmask 0x1 --ctmask 0x1

iptables -t mangle -A GATEWAY_OUTPUT \
    -o "$WAN_IFACE" \
    -m set --match-set vpn_domains dst \
    -j MARK --set-mark 0x1

iptables -t nat -A GATEWAY_POSTROUTE \
    -o wg0 \
    -j MASQUERADE

iptables -t nat -A GATEWAY_POSTROUTE \
    -o "$WAN_IFACE" \
    -j MASQUERADE

iptables -t mangle -A GATEWAY_OUTPUT -p tcp --tcp-flags SYN,RST SYN -m mark --mark 0x1 -j TCPMSS --set-mss 1240

echo "iptables rules configured"
echo ""
echo "=== LOCAL NETWORK PRESERVATION ==="
iptables -L FORWARD -v -n | head -5
echo ""
echo "=== FORWARD ==="
iptables -L GATEWAY_FORWARD -v -n
echo ""
echo "=== Mangle PREROUTING ==="
iptables -t mangle -L GATEWAY_PREROUTE -v -n
echo ""
echo "=== Mangle OUTPUT ==="
iptables -t mangle -L GATEWAY_OUTPUT -v -n
echo ""
echo "=== NAT POSTROUTING ==="
iptables -t nat -L GATEWAY_POSTROUTE -v -n