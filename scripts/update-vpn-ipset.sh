#!/bin/bash

set -e

echo "Updating vpn_domains ipset from resolved IPs..."

if [[ -f "/tmp/ips.txt" ]]; then
    echo "Using locally resolved ips.txt"
    TEMP_FILE="/tmp/ips.txt"
else
    echo "ERROR: /tmp/ips.txt not found!"
    exit 1
fi

echo "Updating vpn_domains ipset..."
count=0
while IFS='=' read -r domain ip; do
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        ipset add vpn_domains "$ip" timeout 3600 -exist
        ((count++)) || true
    fi
done < "$TEMP_FILE"

echo "Added $count IPs to vpn_domains"

if [[ -n "$AGH_URL" ]] && [[ -n "$AGH_PASS" ]]; then
    echo "Updating AdGuard Home DNS rewrites..."
    
    CURRENT_REWRITES=$(curl -s -u "${AGH_USER:-admin}:${AGH_PASS}" "${AGH_URL}/control/rewrite/list")
    
    OUR_DOMAINS=()
    while IFS='=' read -r domain ip; do
        domain=$(echo "$domain" | tr -d '[:space:]')
        if [[ -n "$domain" ]]; then
            OUR_DOMAINS+=("$domain")
        fi
    done < "$TEMP_FILE"
    
    echo "Removing old AdGuard Home rewrites for managed domains..."
    for domain in "${OUR_DOMAINS[@]}"; do
        while IFS= read -r old_ip; do
            if [[ -n "$old_ip" ]]; then
                echo "  Deleting: $domain -> $old_ip"
                curl -s -X POST "${AGH_URL}/control/rewrite/delete" \
                    -u "${AGH_USER:-admin}:${AGH_PASS}" \
                    -H "Content-Type: application/json" \
                    -d "{\"domain\":\"$domain\",\"answer\":\"$old_ip\"}" 2>/dev/null || true
            fi
        done < <(echo "$CURRENT_REWRITES" | jq -r ".[] | select(.domain == \"$domain\") | .answer" 2>/dev/null)
    done
    
    sleep 3
    
    echo "Adding new AdGuard Home rewrites..."
    while IFS='=' read -r domain ip; do
        domain=$(echo "$domain" | tr -d '[:space:]')
        ip=$(echo "$ip" | tr -d '[:space:]')
        
        if [[ -n "$domain" ]] && [[ -n "$ip" ]]; then
            echo "  Adding: $domain -> $ip"
            curl -s -X POST "${AGH_URL}/control/rewrite/add" \
                -u "${AGH_USER:-admin}:${AGH_PASS}" \
                -H "Content-Type: application/json" \
                -d "{\"domain\":\"$domain\",\"answer\":\"$ip\"}" 2>/dev/null || true
        fi
    done < "$TEMP_FILE"
    
    echo "AdGuard Home DNS rewrites synchronized"
fi

rm -f "$TEMP_FILE"
echo "VPN ipset update complete"