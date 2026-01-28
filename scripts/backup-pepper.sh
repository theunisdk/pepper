#!/bin/bash
set -euo pipefail

# Pepper Backup Script
# Creates a backup of Pepper's configuration, credentials, and workspace

# Configuration
SSH_KEY="${MOLTBOT_SSH_KEY:-$HOME/.ssh/moltbot_key.pem}"
HOST="${MOLTBOT_HOST:-13.247.25.37}"
BACKUP_DIR="${HOME}/.pepper-backups/$(date +%Y%m%d-%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Pepper Backup${NC}"
echo "=============="
echo "Host: $HOST"
echo "Backup dir: $BACKUP_DIR"
echo ""

# Check SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    echo "Set MOLTBOT_SSH_KEY environment variable or update this script"
    exit 1
fi

# Create backup directory
echo "Creating backup directory..."
mkdir -p "$BACKUP_DIR"

# Create backup on EC2
echo "Creating backup archive on EC2..."
ssh -i "$SSH_KEY" ubuntu@"$HOST" << 'EOF'
sudo tar -czf /tmp/pepper-backup.tar.gz \
  -C /home/clawd \
  .clawdbot \
  .gog \
  moltbot \
  2>/dev/null || true
sudo chmod 644 /tmp/pepper-backup.tar.gz
EOF

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Backup failed on remote host${NC}"
    exit 1
fi

# Download backup
echo "Downloading backup..."
scp -i "$SSH_KEY" ubuntu@"$HOST":/tmp/pepper-backup.tar.gz "$BACKUP_DIR/"

# Cleanup remote
echo "Cleaning up remote..."
ssh -i "$SSH_KEY" ubuntu@"$HOST" "sudo rm /tmp/pepper-backup.tar.gz"

# Create latest symlink
ln -sfn "$BACKUP_DIR" "$HOME/.pepper-backups/latest"

echo ""
echo -e "${GREEN}✓ Backup complete!${NC}"
echo ""
echo "Backup location: $BACKUP_DIR/pepper-backup.tar.gz"
echo ""
echo "Backup contains:"
echo "  - ~/.clawdbot/ (config, credentials, sessions)"
echo "  - ~/.gog/ (Google OAuth tokens)"
echo "  - ~/moltbot/ (workspace, memory, git history)"
echo ""
echo "To restore: ./scripts/restore-pepper.sh $BACKUP_DIR/pepper-backup.tar.gz"
