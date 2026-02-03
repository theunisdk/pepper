#!/bin/bash
# Command implementations for Docker-based OpenClaw deployments

# Execute terraform command (same as single-instance)
exec_terraform() {
    info "Running terraform for ${CYAN}$INSTANCE_NAME${NC}: $*"

    cd "$INSTANCE_DIR" || {
        error "Failed to cd to $INSTANCE_DIR"
        return 1
    }

    if [[ ! -f "main.tf" ]]; then
        error "Terraform configuration not found in $INSTANCE_DIR"
        return 1
    fi

    AWS_PROFILE="$AWS_PROFILE" terraform "$@"
}

# Get port for a specific bot
get_bot_port() {
    local bot_name="$1"
    parse_bot_config "$INSTANCE_CONFIG" "$bot_name" "port"
}

# List available bots (skips commented lines)
list_bots() {
    local config_file="$1"
    awk '/^bots:/{flag=1; next} flag && /^[a-z]/{exit} flag && /^  - name:/{gsub(/.*- name: */, ""); print}' "$config_file"
}

# Connect to admin UI via SSH tunnel (requires bot name)
exec_connect() {
    local bot_name="${1:-}"

    if [[ -z "$bot_name" ]]; then
        error "Usage: pepper $INSTANCE_NAME connect <bot-name>"
        echo ""
        info "Available bots:"
        list_bots "$INSTANCE_CONFIG" | sed 's/^/  - /'
        return 1
    fi

    # Get port for this bot
    local bot_port=$(get_bot_port "$bot_name")
    if [[ -z "$bot_port" ]]; then
        error "Bot not found: $bot_name"
        info "Available bots:"
        list_bots "$INSTANCE_CONFIG" | sed 's/^/  - /'
        return 1
    fi

    info "Connecting to ${CYAN}$bot_name${NC} on Docker host..."

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found. Run terraform apply first."
        return 1
    fi

    # Check if tunnel already running
    if lsof -i ":$bot_port" >/dev/null 2>&1; then
        warn "Port $bot_port already in use - tunnel may already be running"
    else
        info "Starting SSH tunnel to $OPENCLAW_HOST:$bot_port..."
        ssh -f -N -L "$bot_port:127.0.0.1:$bot_port" \
            -i "$SSH_KEY" \
            "ubuntu@$OPENCLAW_HOST" \
            -o StrictHostKeyChecking=accept-new \
            -o ServerAliveInterval=60 \
            -o ServerAliveCountMax=3 || {
            error "Failed to create SSH tunnel"
            return 1
        }
        success "Tunnel established"
        sleep 1
    fi

    # Open browser
    local url="http://127.0.0.1:$bot_port"
    info "Opening $url ..."

    if command_exists xdg-open; then
        xdg-open "$url" 2>/dev/null &
    elif command_exists open; then
        open "$url"
    elif command_exists wslview; then
        wslview "$url"
    else
        warn "Could not detect browser opener"
        info "Please open manually: $url"
    fi

    success "Done!"
    echo ""
    info "To close the tunnel: pkill -f 'ssh.*$bot_port:127.0.0.1:$bot_port'"
}

# Backup Docker volumes
exec_backup() {
    local bot_name="${1:-}"
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="$BACKUP_DIR/$backup_timestamp"

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    mkdir -p "$backup_path"

    if [[ -z "$bot_name" ]]; then
        info "Backing up ALL bots to $backup_path"
        local bots=$(list_bots "$INSTANCE_CONFIG")
    else
        info "Backing up ${CYAN}$bot_name${NC} to $backup_path"
        local bots="$bot_name"
    fi

    # Create backup on remote
    info "Creating backup archives on Docker host..."
    ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" << EOF
mkdir -p /tmp/openclaw-backup-$backup_timestamp

for bot in $bots; do
    echo "Backing up \$bot volumes..."
    for suffix in config gog workspace; do
        vol="openclaw_\${bot}-\${suffix}"
        if docker volume ls --format '{{.Name}}' | grep -q "^\$vol\$"; then
            docker run --rm \
                -v \$vol:/source:ro \
                -v /tmp/openclaw-backup-$backup_timestamp:/backup \
                alpine tar czf /backup/\${vol}.tar.gz -C /source . 2>/dev/null || true
        fi
    done
done

chmod -R 644 /tmp/openclaw-backup-$backup_timestamp/*
EOF

    if [ $? -ne 0 ]; then
        error "Backup failed on remote host"
        return 1
    fi

    # Download backups
    info "Downloading backups..."
    scp -i "$SSH_KEY" -r \
        "ubuntu@$OPENCLAW_HOST:/tmp/openclaw-backup-$backup_timestamp/*" \
        "$backup_path/" || {
        error "Failed to download backups"
        return 1
    }

    # Cleanup remote
    ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
        "rm -rf /tmp/openclaw-backup-$backup_timestamp"

    # Create latest symlink
    ln -sfn "$backup_path" "$BACKUP_DIR/latest"

    success "Backup complete!"
    echo ""
    info "Backup location: $backup_path/"
    ls -la "$backup_path/"
}

# Restore Docker volumes from backup
exec_restore() {
    local bot_name="${1:-}"
    local backup_dir="${2:-$BACKUP_DIR/latest}"

    if [[ -z "$bot_name" ]]; then
        error "Usage: pepper $INSTANCE_NAME restore <bot-name> [backup-dir]"
        return 1
    fi

    if [[ ! -d "$backup_dir" ]]; then
        error "Backup directory not found: $backup_dir"
        return 1
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    info "Restoring ${CYAN}$bot_name${NC} from: $backup_dir"
    warn "This will stop the container and overwrite current data!"
    echo ""

    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Restore cancelled."
        return 0
    fi

    # Stop container
    info "Stopping $bot_name container..."
    ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
        "docker compose -f /opt/openclaw/docker-compose.yml stop $bot_name"

    # Upload backups
    info "Uploading backups..."
    scp -i "$SSH_KEY" \
        "$backup_dir/openclaw_${bot_name}-"*.tar.gz \
        "ubuntu@$OPENCLAW_HOST:/tmp/" 2>/dev/null || true

    # Restore volumes
    info "Restoring volumes..."
    ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" << EOF
for suffix in config gog workspace; do
    vol="openclaw_${bot_name}-\${suffix}"
    backup_file="/tmp/openclaw_${bot_name}-\${suffix}.tar.gz"

    if [[ -f "\$backup_file" ]]; then
        echo "Restoring \$vol..."
        # Clear existing volume data
        docker run --rm -v \$vol:/data alpine sh -c "rm -rf /data/*" 2>/dev/null || true
        # Restore from backup
        docker run --rm \
            -v \$vol:/data \
            -v /tmp:/backup \
            alpine tar xzf /backup/openclaw_${bot_name}-\${suffix}.tar.gz -C /data
        rm "\$backup_file"
    fi
done
EOF

    # Start container
    info "Starting $bot_name container..."
    ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
        "docker compose -f /opt/openclaw/docker-compose.yml start $bot_name"

    success "Restore complete!"
}

# SSH to Docker host
exec_ssh() {
    info "SSH to Docker host..."

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST"
}

# Execute command in bot container
exec_shell() {
    local bot_name="${1:-}"

    if [[ -z "$bot_name" ]]; then
        error "Usage: pepper $INSTANCE_NAME shell <bot-name>"
        info "Available bots:"
        list_bots "$INSTANCE_CONFIG" | sed 's/^/  - /'
        return 1
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    info "Opening shell in ${CYAN}$bot_name${NC} container..."
    ssh -t -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
        "docker compose -f /opt/openclaw/docker-compose.yml exec $bot_name bash"
}

# Run onboarding for a bot
exec_onboard() {
    local bot_name="${1:-}"

    if [[ -z "$bot_name" ]]; then
        error "Usage: pepper $INSTANCE_NAME onboard <bot-name>"
        info "Available bots:"
        list_bots "$INSTANCE_CONFIG" | sed 's/^/  - /'
        return 1
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    info "Running onboarding for ${CYAN}$bot_name${NC}..."
    ssh -t -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
        "docker compose -f /opt/openclaw/docker-compose.yml exec -it $bot_name openclaw onboard"
}

# View logs
exec_logs() {
    local bot_name="${1:-}"
    local tail_lines="${2:-100}"

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    if [[ -z "$bot_name" ]]; then
        info "Viewing logs for ALL bots..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker compose -f /opt/openclaw/docker-compose.yml logs -f --tail=$tail_lines"
    else
        info "Viewing logs for ${CYAN}$bot_name${NC}..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker compose -f /opt/openclaw/docker-compose.yml logs -f --tail=$tail_lines $bot_name"
    fi
}

# Show Docker host and container status
exec_status() {
    echo ""
    echo "${CYAN}=== Docker Host Status: $INSTANCE_NAME ===${NC}"
    echo ""
    echo "Host IP:        $OPENCLAW_HOST"
    echo "SSH Key:        $SSH_KEY"
    echo "AWS Profile:    $AWS_PROFILE"
    echo "AWS Region:     $AWS_REGION"
    echo "Backup Dir:     $BACKUP_DIR"
    echo ""
    echo "Configured bots:"
    list_bots "$INSTANCE_CONFIG" | while read -r bot; do
        local port=$(get_bot_port "$bot")
        echo "  - $bot (port: $port)"
    done
    echo ""

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        warn "Docker host not yet deployed or Terraform not initialized"
        echo ""
        info "To deploy:"
        info "  pepper $INSTANCE_NAME terraform init"
        info "  pepper $INSTANCE_NAME terraform apply"
        return 0
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    info "Checking Docker host connectivity..."
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 "ubuntu@$OPENCLAW_HOST" "echo connected" 2>/dev/null; then
        success "Docker host is reachable"
        echo ""

        info "Container status:"
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker compose -f /opt/openclaw/docker-compose.yml ps" 2>&1 || true

        echo ""
        info "Resource usage:"
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'" 2>&1 || true
    else
        error "Cannot connect to Docker host"
    fi
}

# Start all or specific container
exec_start() {
    local bot_name="${1:-}"

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    if [[ -z "$bot_name" ]]; then
        info "Starting all containers..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "sudo systemctl start openclaw-docker"
    else
        info "Starting ${CYAN}$bot_name${NC}..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker compose -f /opt/openclaw/docker-compose.yml start $bot_name"
    fi

    success "Done!"
}

# Stop all or specific container
exec_stop() {
    local bot_name="${1:-}"

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    if [[ -z "$bot_name" ]]; then
        info "Stopping all containers..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "sudo systemctl stop openclaw-docker"
    else
        info "Stopping ${CYAN}$bot_name${NC}..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker compose -f /opt/openclaw/docker-compose.yml stop $bot_name"
    fi

    success "Done!"
}

# Restart all or specific container
exec_restart() {
    local bot_name="${1:-}"

    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$OPENCLAW_HOST" == "UNKNOWN" ]]; then
        error "Docker host IP not found"
        return 1
    fi

    if [[ -z "$bot_name" ]]; then
        info "Restarting all containers..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "sudo systemctl restart openclaw-docker"
    else
        info "Restarting ${CYAN}$bot_name${NC}..."
        ssh -i "$SSH_KEY" "ubuntu@$OPENCLAW_HOST" \
            "docker compose -f /opt/openclaw/docker-compose.yml restart $bot_name"
    fi

    success "Done!"
}
