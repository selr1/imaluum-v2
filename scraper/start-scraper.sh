#!/bin/bash

# Configuration
# Find .env.local
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Try root .env.local first (since we usually run from root context in dev)
ENV_FILE="$SCRIPT_DIR/../.env.local"
if [ ! -f "$ENV_FILE" ]; then
    # Fallback to local dir
    ENV_FILE="$SCRIPT_DIR/.env.local"
fi

if [ -f "$ENV_FILE" ]; then
    echo "Loading config from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "⚠️  No .env.local found! Please ensure variables are set in environment."
fi

# Validation
if [ -z "$NEXT_PUBLIC_SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    echo "❌ Error: Supabase credentials missing."
    echo "Please set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env.local"
    exit 1
fi

# Set defaults if not provided by .env.local or environment
PORT=${PORT:-3001}
TUNNEL_INTERVAL=${TUNNEL_INTERVAL:-3000} # 50 minutes rotation
TUNNEL_HOST=${TUNNEL_HOST:-"a.pinggy.io"}

echo "--- i-Ma'luum Scraper Launcher (Rotating Tunnel) ---"

# Helper: Update Supabase
update_supabase() {
    local url="$1"
    echo "Updating Supabase with: $url"
    curl -s -X POST "${NEXT_PUBLIC_SUPABASE_URL}/rest/v1/bot_settings" \
        -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
        -H "Content-Type: application/json" \
        -H "Prefer: resolution=merge-duplicates" \
        -d "{\"key\": \"imaluum_scraper_url\", \"value\": {\"url\": \"${url}\", \"updated_at\": \"$(date -Iseconds)\"}}" > /dev/null
}

# Helper: Start Tunnel
start_tunnel() {
    echo "Starting Tunnel..."
    tmpfile=$(mktemp)
    # Start ssh tunnel in background
    ssh -p 443 -R0:localhost:$PORT -o StrictHostKeyChecking=no -o ServerAliveInterval=30 a.pinggy.io > "$tmpfile" 2>&1 &
    local tpid=$!
    
    local url=""
    local counter=0
    # Wait for URL
    while [ -z "$url" ] && [ $counter -lt 45 ]; do
        sleep 1
        url=$(grep -oE 'https://[a-z0-9-]+\.[a-z]+\.free\.pinggy\.link' "$tmpfile" | head -1)
        counter=$((counter+1))
    done
    
    rm -f "$tmpfile"
    
    if [ -n "$url" ]; then
        echo "✅ Tunnel Online: $url"
        update_supabase "$url"
        echo "$tpid"
    else
        echo "❌ Tunnel failed."
        echo ""
    fi
}

start_scraper() {
    echo "Starting Scraper on port $PORT..."
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
        kill $(lsof -Pi :$PORT -sTCP:LISTEN -t)
    fi
    nohup node server.js > scraper.log 2>&1 &
    SCRAPER_PID=$!
    echo "Scraper started (PID: $SCRAPER_PID)"
}

# Main Logic
start_scraper

CURRENT_TUNNEL_PID=$(start_tunnel)
LAST_ROTATION=$(date +%s)

while true; do
    # 1. Check if Scraper is still running
    if ! kill -0 "$SCRAPER_PID" 2>/dev/null; then
        echo "⚠️ Scraper process died. Restarting..."
        start_scraper
    fi

    # 2. Check Tunnel Rotation Time
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_ROTATION))

    if [ $DIFF -ge $TUNNEL_INTERVAL ]; then
        echo "Rotating tunnel..."
        OLD_PID=$CURRENT_TUNNEL_PID
        NEW_PID=$(start_tunnel)
        
        if [ -n "$NEW_PID" ]; then
            CURRENT_TUNNEL_PID=$NEW_PID
            LAST_ROTATION=$NOW
            sleep 5
            [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null
            echo "Tunnel rotated successfully."
        else
            echo "Tunnel rotation failed, retrying next cycle."
        fi
    fi

    sleep 10
done
