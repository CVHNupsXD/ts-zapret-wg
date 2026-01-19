#!/bin/bash

set -euo pipefail

DOH_SERVER="https://public.dns.iij.jp/dns-query" # IIJ Public DoH server
INPUT_FILE="/config/domains.txt"
OUTPUT_FILE="/tmp/ips.txt"
TEMP_FILE="$(mktemp)"

echo "Starting domain resolution using (${DOH_SERVER})..."

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: $INPUT_FILE not found!"
    echo "Please ensure domains.txt is mounted in /config/"
    exit 1
fi

if ! command -v doge &> /dev/null; then
    echo "ERROR: 'doge' DNS tool not found."
    exit 1
fi

> "$TEMP_FILE"

while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | xargs)

    if [[ -z "$line" ]] || [[ "$line" =~ ^# ]]; then
        continue
    fi
    
    domain="$line"
    echo "Resolving: $domain"
    
    resolved=false
    for attempt in 1 2 3; do
        if result=$(doge A "$domain" --https @"$DOH_SERVER" --short 2>/dev/null); then
            ip=$(echo "$result" | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n 1)
            if [[ -n "$ip" ]]; then
                echo "  ✓ $ip"
                echo "$domain=$ip" >> "$TEMP_FILE"
                resolved=true
                break
            fi
        fi
        sleep 1
    done
    
    if [[ "$resolved" == "false" ]]; then
        echo "  ✗ Failed to resolve" >&2
    fi
done < "$INPUT_FILE"

sort "$TEMP_FILE" > "$OUTPUT_FILE"
rm -f "$TEMP_FILE"

line_count=$(wc -l <"$OUTPUT_FILE" | xargs)
echo "Completed! Resolved $line_count domains"

if [[ $line_count -eq 0 ]]; then
    echo "WARNING: No domains were resolved successfully"
    exit 1
fi

exit 0
