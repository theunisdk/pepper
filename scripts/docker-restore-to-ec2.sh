#!/bin/bash
# Restore local Docker backup to EC2 Docker host
# Usage: ./scripts/docker-restore-to-ec2.sh <instance-name> <ec2-instance> [backup-dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

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
EC2_INSTANCE="${2:-}"
BACKUP_DIR="${3:-$HOME/.openclaw-backups/$INSTANCE_NAME/latest}"

if [[ -z "$INSTANCE_NAME" || -z "$EC2_INSTANCE" ]]; then
    error "Usage: $0 <instance-name> <ec2-instance> [backup-dir]"
    echo ""
    echo "Arguments:"
    echo "  instance-name   Name of the bot (e.g., iris)"
    echo "  ec2-instance    Name of the EC2 pepper instance (e.g., test, pepper)"
    echo "  backup-dir      Path to backup directory (default: ~/.openclaw-backups/<instance>/latest)"
    echo ""
    echo "Examples:"
    echo "  $0 iris test                           # Restore iris to 'test' EC2 instance"
    echo "  $0 iris pepper /path/to/backup         # Restore from specific backup"
    echo ""
    echo "Available backups:"
    find "$HOME/.openclaw-backups" -name "manifest.json" -exec dirname {} \; 2>/dev/null | sort -r | head -10
    exit 1
fi

# Load EC2 instance configuration
EC2_CONFIG="$ROOT_DIR/instances/$EC2_INSTANCE/instance.yaml"
if [[ ! -f "$EC2_CONFIG" ]]; then
    error "EC2 instance configuration not found: $EC2_CONFIG"
    exit 1
fi

# Check backup exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Parse EC2 instance config
get_yaml_value() {
    local file="$1"
    local key="$2"
    grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"'
}

get_nested_yaml_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    awk "/^${section}:/{flag=1; next} /^[a-z]/{flag=0} flag && /${key}:/{gsub(/.*: */, \"\"); print; exit}" "$file" | tr -d '"'
}

# Get SSH key path
SSH_KEY=$(get_nested_yaml_value "$EC2_CONFIG" "ssh" "key_path")
SSH_KEY="${SSH_KEY/#\~/$HOME}"

if [[ ! -f "$SSH_KEY" ]]; then
    error "SSH key not found: $SSH_KEY"
    exit 1
fi

# Get EC2 IP from Terraform output
EC2_DIR="$ROOT_DIR/instances/$EC2_INSTANCE"
if [[ -f "$EC2_DIR/terraform.tfstate" ]] || [[ -d "$EC2_DIR/.terraform" ]]; then
    EC2_IP=$(cd "$EC2_DIR" && terraform output -raw instance_public_ip 2>/dev/null || echo "")
fi

if [[ -z "$EC2_IP" ]]; then
    error "Could not determine EC2 IP. Run terraform apply first."
    exit 1
fi

# Determine deployment type
DEPLOY_TYPE=$(get_nested_yaml_value "$EC2_CONFIG" "deployment" "type")

info "Restoring ${CYAN}$INSTANCE_NAME${NC} to EC2 instance ${CYAN}$EC2_INSTANCE${NC}"
info "Backup source: $BACKUP_DIR"
info "EC2 IP: $EC2_IP"
info "Deployment type: ${DEPLOY_TYPE:-single-instance}"
echo ""

warn "This will overwrite existing data on the EC2 instance!"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Restore cancelled."
    exit 0
fi

# Upload backup files
info "Uploading backup files to EC2..."
REMOTE_BACKUP_DIR="/tmp/openclaw-restore-$$"
ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" "mkdir -p $REMOTE_BACKUP_DIR"
scp -i "$SSH_KEY" "$BACKUP_DIR"/*.tar.gz "ubuntu@$EC2_IP:$REMOTE_BACKUP_DIR/"

if [[ "$DEPLOY_TYPE" == "docker-host" || "$DEPLOY_TYPE" == "docker-local" ]]; then
    # Docker host deployment - restore to Docker volumes
    info "Restoring to Docker volumes..."

    # Stop container
    ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" \
        "docker stop openclaw-$INSTANCE_NAME 2>/dev/null || true"

    # Restore each volume
    for suffix in config gogcli workspace; do
        BACKUP_FILE="$REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-${suffix}.tar.gz"
        VOLUME_NAME="openclaw_${INSTANCE_NAME}-${suffix}"

        info "Restoring $VOLUME_NAME..."
        ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" << EOF
if [[ -f "$BACKUP_FILE" ]]; then
    # Create volume if it doesn't exist
    docker volume create $VOLUME_NAME 2>/dev/null || true
    # Clear and restore
    docker run --rm -v $VOLUME_NAME:/data alpine sh -c "rm -rf /data/*"
    docker run --rm -v $VOLUME_NAME:/data -v $REMOTE_BACKUP_DIR:/backup alpine tar xzf /backup/openclaw_${INSTANCE_NAME}-${suffix}.tar.gz -C /data
    echo "  Restored: $VOLUME_NAME"
fi
EOF
    done

    # Start container
    info "Starting container..."
    ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" \
        "docker start openclaw-$INSTANCE_NAME 2>/dev/null || echo 'Container not found - may need to create it'"

else
    # Single EC2 instance - restore directly to filesystem
    info "Restoring to single EC2 instance..."

    # Stop openclaw service
    ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" \
        "sudo systemctl stop openclaw 2>/dev/null || true"

    # Restore config
    if ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" "test -f $REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-config.tar.gz"; then
        info "Restoring OpenClaw config..."
        ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" << EOF
sudo -u clawd bash -c "
    rm -rf /home/clawd/.openclaw/*
    tar xzf $REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-config.tar.gz -C /home/clawd/.openclaw/
"
EOF
    fi

    # Restore gogcli
    if ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" "test -f $REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-gogcli.tar.gz"; then
        info "Restoring gog config..."
        ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" << EOF
sudo -u clawd bash -c "
    mkdir -p /home/clawd/.config/gogcli
    rm -rf /home/clawd/.config/gogcli/*
    tar xzf $REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-gogcli.tar.gz -C /home/clawd/.config/gogcli/
"
EOF
    fi

    # Restore workspace
    if ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" "test -f $REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-workspace.tar.gz"; then
        info "Restoring workspace..."
        ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" << EOF
sudo -u clawd bash -c "
    rm -rf /home/clawd/openclaw/*
    tar xzf $REMOTE_BACKUP_DIR/openclaw_${INSTANCE_NAME}-workspace.tar.gz -C /home/clawd/openclaw/
"
EOF
    fi

    # Start openclaw service
    info "Starting OpenClaw service..."
    ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" \
        "sudo systemctl start openclaw"
fi

# Cleanup
info "Cleaning up..."
ssh -i "$SSH_KEY" "ubuntu@$EC2_IP" "rm -rf $REMOTE_BACKUP_DIR"

echo ""
success "Restore complete!"
echo ""
info "To verify:"
if [[ "$DEPLOY_TYPE" == "docker-host" || "$DEPLOY_TYPE" == "docker-local" ]]; then
    info "  ssh -i $SSH_KEY ubuntu@$EC2_IP 'docker logs openclaw-$INSTANCE_NAME'"
else
    info "  ssh -i $SSH_KEY ubuntu@$EC2_IP 'sudo journalctl -u openclaw -f'"
fi
