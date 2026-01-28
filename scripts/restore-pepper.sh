#!/bin/bash
set -euo pipefail

# Pepper Restore Script
# Restores Pepper's configuration, credentials, and workspace from backup

# Configuration
SSH_KEY="${MOLTBOT_SSH_KEY:-$HOME/.ssh/moltbot_key.pem}"
HOST="${MOLTBOT_HOST:-13.247.25.37}"
BACKUP_FILE="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check arguments
if [[ -z "$BACKUP_FILE" ]]; then
    echo -e "${RED}Error: Backup file not specified${NC}"
    echo "Usage: $0 <path-to-backup.tar.gz>"
    echo ""
    echo "Available backups:"
    ls -lh "$HOME/.pepper-backups/" 2>/dev/null | grep -v total || echo "  No backups found"
    exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo -e "${RED}Error: Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

# Check SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    exit 1
fi

echo -e "${GREEN}Pepper Restore${NC}"
echo "=============="
echo "Backup file: $BACKUP_FILE"
echo "Target host: $HOST"
echo ""

# Confirmation
read -p "This will overwrite Pepper's current configuration. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Upload backup
echo "Uploading backup to EC2..."
scp -i "$SSH_KEY" "$BACKUP_FILE" ubuntu@"$HOST":/tmp/pepper-backup.tar.gz

# Stop service, restore, restart
echo "Restoring on EC2..."
ssh -i "$SSH_KEY" ubuntu@"$HOST" << 'EOF'
# Stop moltbot service
echo "Stopping moltbot service..."
sudo systemctl stop moltbot

# Backup current config (just in case)
sudo tar -czf /tmp/pepper-before-restore.tar.gz -C /home/clawd .clawdbot .gog moltbot 2>/dev/null || true

# Remove old data
echo "Removing old configuration..."
sudo rm -rf /home/clawd/.clawdbot /home/clawd/.gog /home/clawd/moltbot

# Extract backup
echo "Extracting backup..."
sudo tar -xzf /tmp/pepper-backup.tar.gz -C /home/clawd/

# Fix permissions
echo "Fixing permissions..."
sudo chown -R clawd:clawd /home/clawd/.clawdbot /home/clawd/.gog /home/clawd/moltbot

# Cleanup
sudo rm /tmp/pepper-backup.tar.gz

# Start service
echo "Starting moltbot service..."
sudo systemctl start moltbot

# Wait a moment
sleep 2

# Check status
sudo systemctl status moltbot --no-pager || true
EOF

echo ""
echo -e "${GREEN}✓ Restore complete!${NC}"
echo ""
echo "Service status:"
ssh -i "$SSH_KEY" ubuntu@"$HOST" "sudo systemctl is-active moltbot"

echo ""
echo "To verify:"
echo "  ssh -i $SSH_KEY ubuntu@$HOST"
echo "  sudo journalctl -u moltbot -f"
