#!/bin/bash

# Configuration
PORT=3001
TUNNEL_INTERVAL=3000 # 50 minutes rotation

# Supabase Credentials (from dopdop project)
NEXT_PUBLIC_SUPABASE_URL="https://vcwdryhfqriswkmpqzlv.supabase.co"
SUPABASE_SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZjd2RyeWhmcXJpc3drbXBxemx2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MDE0NTg5NCwiZXhwIjoyMDg1NzIxODk0fQ.DAu2w4xPcvdfixN617PzFKFRQJx3kZ3HKgaOSOWfTBs"

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
