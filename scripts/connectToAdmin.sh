#!/bin/bash
set -euo pipefail

# Moltbot Admin Connection Script
# Creates SSH tunnel and opens browser to admin UI

# Configuration (update these if your setup differs)
SSH_KEY="${MOLTBOT_SSH_KEY:-$HOME/.ssh/moltbot_key.pem}"
HOST="${MOLTBOT_HOST:-13.247.25.37}"
PORT="${MOLTBOT_PORT:-18789}"
SSH_USER="${MOLTBOT_SSH_USER:-ubuntu}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Moltbot Admin Connection${NC}"
echo "========================="
echo "Host: $HOST"
echo "Port: $PORT"
echo "SSH Key: $SSH_KEY"
echo ""

# Check SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    echo "Set MOLTBOT_SSH_KEY environment variable or update this script"
    exit 1
fi

# Check if tunnel already running
if lsof -i ":$PORT" >/dev/null 2>&1; then
    echo -e "${YELLOW}Port $PORT already in use - tunnel may already be running${NC}"
    echo "Opening browser..."
else
    echo "Starting SSH tunnel..."
    # Start tunnel in background
    ssh -f -N -L "$PORT:127.0.0.1:$PORT" -i "$SSH_KEY" "$SSH_USER@$HOST" \
        -o StrictHostKeyChecking=accept-new \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=3

    echo -e "${GREEN}Tunnel established${NC}"

    # Wait for tunnel to be ready
    sleep 1
fi

# Open browser
URL="http://127.0.0.1:$PORT"
echo "Opening $URL ..."

if command -v xdg-open >/dev/null 2>&1; then
    # Linux
    xdg-open "$URL" 2>/dev/null &
elif command -v open >/dev/null 2>&1; then
    # macOS
    open "$URL"
elif command -v wslview >/dev/null 2>&1; then
    # WSL
    wslview "$URL"
else
    echo -e "${YELLOW}Could not detect browser opener${NC}"
    echo "Please open manually: $URL"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo "To close the tunnel later:"
echo "  pkill -f 'ssh.*$PORT:127.0.0.1:$PORT'"
