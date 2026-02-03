#!/bin/bash
# Backup local Docker OpenClaw volumes
# Usage: ./scripts/docker-backup.sh <instance-name> [backup-dir]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

INSTANCE_NAME="${1:-}"
BACKUP_BASE="${2:-$HOME/.openclaw-backups}"

if [[ -z "$INSTANCE_NAME" ]]; then
    error "Usage: $0 <instance-name> [backup-dir]"
    echo ""
    echo "Examples:"
    echo "  $0 iris                    # Backup iris to ~/.openclaw-backups/"
    echo "  $0 iris /tmp/backups       # Backup iris to /tmp/backups/"
    echo ""
    echo "Available local volumes:"
    docker volume ls --format '{{.Name}}' | grep "^openclaw_" | sed 's/openclaw_/  /' | sed 's/-config$//' | sed 's/-gogcli$//' | sed 's/-workspace$//' | sort -u
    exit 1
fi

BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_BASE/$INSTANCE_NAME/$BACKUP_TIMESTAMP"

info "Backing up local Docker instance: ${CYAN}$INSTANCE_NAME${NC}"
info "Backup directory: $BACKUP_DIR"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Volumes to backup
VOLUMES=(
    "openclaw_${INSTANCE_NAME}-config"
    "openclaw_${INSTANCE_NAME}-gogcli"
    "openclaw_${INSTANCE_NAME}-workspace"
)

# Check if volumes exist
for vol in "${VOLUMES[@]}"; do
    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
        warn "Volume not found: $vol (skipping)"
    fi
done

# Stop container if running (to ensure consistent backup)
CONTAINER_NAME="openclaw-${INSTANCE_NAME}"
CONTAINER_WAS_RUNNING=false

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Stopping container $CONTAINER_NAME for consistent backup..."
    docker stop "$CONTAINER_NAME" >/dev/null
    CONTAINER_WAS_RUNNING=true
fi

# Backup each volume
for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        info "Backing up $vol..."
        docker run --rm \
            -v "$vol":/source:ro \
            -v "$BACKUP_DIR":/backup \
            alpine tar czf "/backup/${vol}.tar.gz" -C /source .
        success "  -> ${vol}.tar.gz"
    fi
done

# Restart container if it was running
if [[ "$CONTAINER_WAS_RUNNING" == "true" ]]; then
    info "Restarting container $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME" >/dev/null
fi

# Create latest symlink
ln -sfn "$BACKUP_DIR" "$BACKUP_BASE/$INSTANCE_NAME/latest"

# Create manifest
cat > "$BACKUP_DIR/manifest.json" << EOF
{
    "instance": "$INSTANCE_NAME",
    "timestamp": "$BACKUP_TIMESTAMP",
    "date": "$(date -Iseconds)",
    "volumes": [
        "openclaw_${INSTANCE_NAME}-config",
        "openclaw_${INSTANCE_NAME}-gogcli",
        "openclaw_${INSTANCE_NAME}-workspace"
    ],
    "source": "local-docker"
}
EOF

echo ""
success "Backup complete!"
echo ""
info "Backup location: $BACKUP_DIR/"
ls -lh "$BACKUP_DIR/"
echo ""
info "To restore to EC2:"
info "  ./scripts/docker-restore-to-ec2.sh $INSTANCE_NAME <ec2-instance> $BACKUP_DIR"
