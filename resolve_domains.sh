#!/usr/bin/env bash
set -euo pipefail


DOH_SERVERS=(
    "https://public.dns.iij.jp/dns-query"
)
INPUT_FILE="domains.txt"
OUTPUT_FILE="ips.txt"
TEMP_FILE="$(mktemp)"

echo "Starting domain resolution using JP DoH..."

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found!"
    exit 1
fi

if ! command -v dog &> /dev/null; then
    echo "Error: 'dog' DNS tool not found. Please install it first."
    echo "GitHub: https://github.com/ogham/dog"
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
    for doh_url in "${DOH_SERVERS[@]}"; do
        for attempt in 1 2 3; do
            if result=$(dog A "$domain" --https @"$doh_url" --short 2>/dev/null); then
                ip=$(echo "$result" | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n 1)
                if [[ -n "$ip" ]]; then
                    echo "$domain=$ip" >> "$TEMP_FILE"
                    resolved=true
                    break 2
                fi
            fi
            sleep 1
        done
        if [[ "$resolved" == "false" ]]; then
            echo "Trying backup DNS for $domain..."
        fi
    done
    
    if [[ "$resolved" == "false" ]]; then
        echo "Warning: Failed to resolve $domain with all DNS servers" >&2
    fi
done < "$INPUT_FILE"

sort "$TEMP_FILE" > "$OUTPUT_FILE"

rm -f "$TEMP_FILE"

line_count=$(wc -l < "$OUTPUT_FILE" | xargs)
echo "Completed! Generated $line_count entries in $OUTPUT_FILE"
