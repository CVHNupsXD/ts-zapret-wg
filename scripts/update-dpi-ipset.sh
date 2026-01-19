#!/bin/bash

#
# Populate dpi_domains ipset by resolving domains from zapret-hosts-user.txt
# This ipset is used by iptables to send traffic to zapret NFQUEUE
#

set -e

echo "Updating dpi_domains ipset..."

ZAPRET_HOSTS="/config/zapret-hosts-user.txt"

if [[ ! -f "$ZAPRET_HOSTS" ]]; then
    echo "WARNING: $ZAPRET_HOSTS not found, skipping DPI ipset update"
    exit 0
fi

count=0
while IFS= read -r line; do
    line=$(echo "$line" | xargs)
    
    if [[ -z "$line" ]] || [[ "$line" =~ ^# ]]; then
        continue
    fi
    
    domain="${line#\*.}"
    
    if [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        ipset add dpi_domains "$domain" -exist
        ((count++)) || true
    else
        if ips=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.' | sort -u | head -5); then
            while IFS= read -r ip; do
                if [[ -n "$ip" ]]; then
                    ipset add dpi_domains "$ip" -exist
                    ((count++)) || true
                fi
            done <<< "$ips"
        else
            echo "  Failed to resolve: $domain"
        fi
    fi
done < "$ZAPRET_HOSTS"

echo "Added $count IPs to dpi_domains"
echo ""
echo "Current dpi_domains:"
ipset list dpi_domains -t
