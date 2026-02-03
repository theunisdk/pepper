#!/bin/bash
# Common functions for pepper (OpenClaw instance management)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Show usage
show_usage() {
    cat <<EOF
${CYAN}Pepper - OpenClaw Instance Manager${NC}

Usage:
  pepper <instance> <command> [args...]

${YELLOW}Instances:${NC}
  List available: ls -1 instances/ | grep -v ".example"

${YELLOW}Commands:${NC}
  terraform [args]  - Run terraform commands for this instance
  connect          - Connect to admin UI via SSH tunnel
  backup           - Backup instance configuration
  restore [file]   - Restore from backup
  ssh              - SSH into instance
  status           - Show instance status

${YELLOW}Examples:${NC}
  pepper myhost terraform apply
  pepper myhost connect
  pepper myhost backup
  pepper myhost ssh

${YELLOW}Create a new instance:${NC}
  scripts/create-docker-host

EOF
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate instance name
validate_instance_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9-]+$ ]]; then
        error "Invalid instance name: $name"
        error "Must contain only lowercase letters, numbers, and hyphens"
        return 1
    fi
    return 0
}
