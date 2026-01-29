#!/bin/bash
# Command implementations for moltbot instances

# Execute terraform command
exec_terraform() {
    info "Running terraform for ${CYAN}$INSTANCE_NAME${NC}: $*"

    cd "$INSTANCE_DIR" || {
        error "Failed to cd to $INSTANCE_DIR"
        return 1
    }

    # Check if main.tf exists
    if [[ ! -f "main.tf" ]]; then
        error "Terraform configuration not found in $INSTANCE_DIR"
        error "Expected main.tf to exist"
        return 1
    fi

    # Run terraform with AWS profile
    AWS_PROFILE="$AWS_PROFILE" terraform "$@"
}

# Connect to admin UI via SSH tunnel
exec_connect() {
    info "Connecting to ${CYAN}$INSTANCE_NAME${NC} admin UI..."

    # Validate configuration
    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$MOLTBOT_HOST" == "UNKNOWN" ]]; then
        error "Instance IP not found"
        error "Make sure Terraform has been applied: moltbot $INSTANCE_NAME terraform apply"
        return 1
    fi

    # Check if tunnel already running
    if lsof -i ":$MOLTBOT_PORT" >/dev/null 2>&1; then
        warn "Port $MOLTBOT_PORT already in use - tunnel may already be running"
        info "Opening browser..."
    else
        info "Starting SSH tunnel to $MOLTBOT_HOST..."
        ssh -f -N -L "$MOLTBOT_PORT:127.0.0.1:$MOLTBOT_PORT" \
            -i "$SSH_KEY" \
            "ubuntu@$MOLTBOT_HOST" \
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
    local url="http://127.0.0.1:$MOLTBOT_PORT"
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
    info "To close the tunnel later:"
    info "  pkill -f 'ssh.*$MOLTBOT_PORT:127.0.0.1:$MOLTBOT_PORT'"
}

# Backup instance
exec_backup() {
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="$BACKUP_DIR/$backup_timestamp"

    info "Backing up ${CYAN}$INSTANCE_NAME${NC} to $backup_path"

    # Validate configuration
    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$MOLTBOT_HOST" == "UNKNOWN" ]]; then
        error "Instance IP not found"
        return 1
    fi

    # Create backup directory
    mkdir -p "$backup_path"

    # Create backup on EC2
    info "Creating backup archive on EC2..."
    ssh -i "$SSH_KEY" "ubuntu@$MOLTBOT_HOST" << EOF
sudo tar -czf /tmp/${INSTANCE_NAME}-backup.tar.gz \
  -C /home/$MOLTBOT_USER \
  .clawdbot \
  .gog \
  moltbot \
  2>/dev/null || true
sudo chmod 644 /tmp/${INSTANCE_NAME}-backup.tar.gz
EOF

    if [ $? -ne 0 ]; then
        error "Backup failed on remote host"
        return 1
    fi

    # Download backup
    info "Downloading backup..."
    scp -i "$SSH_KEY" \
        "ubuntu@$MOLTBOT_HOST:/tmp/${INSTANCE_NAME}-backup.tar.gz" \
        "$backup_path/" || {
        error "Failed to download backup"
        return 1
    }

    # Cleanup remote
    info "Cleaning up remote..."
    ssh -i "$SSH_KEY" "ubuntu@$MOLTBOT_HOST" \
        "sudo rm /tmp/${INSTANCE_NAME}-backup.tar.gz"

    # Create latest symlink
    ln -sfn "$backup_path" "$BACKUP_DIR/latest"

    success "Backup complete!"
    echo ""
    info "Backup location: $backup_path/${INSTANCE_NAME}-backup.tar.gz"
    info "Backup contains:"
    info "  - ~/.clawdbot/ (config, credentials, sessions)"
    info "  - ~/.gog/ (Google OAuth tokens)"
    info "  - ~/moltbot/ (workspace, memory, git history)"
    echo ""
    info "To restore: moltbot $INSTANCE_NAME restore $backup_path/${INSTANCE_NAME}-backup.tar.gz"
}

# Restore instance from backup
exec_restore() {
    local backup_file="${1:-$BACKUP_DIR/latest/${INSTANCE_NAME}-backup.tar.gz}"

    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        error ""
        error "Available backups:"
        if [[ -d "$BACKUP_DIR" ]]; then
            ls -lh "$BACKUP_DIR" 2>/dev/null | grep -v total | sed 's/^/  /' || echo "  None"
        else
            echo "  None"
        fi
        return 1
    fi

    # Validate configuration
    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$MOLTBOT_HOST" == "UNKNOWN" ]]; then
        error "Instance IP not found"
        return 1
    fi

    info "Restoring ${CYAN}$INSTANCE_NAME${NC} from: $backup_file"
    warn "This will overwrite current configuration!"
    echo ""

    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Restore cancelled."
        return 0
    fi

    # Upload and restore
    info "Uploading backup to EC2..."
    scp -i "$SSH_KEY" "$backup_file" "ubuntu@$MOLTBOT_HOST:/tmp/${INSTANCE_NAME}-backup.tar.gz" || {
        error "Failed to upload backup"
        return 1
    }

    info "Restoring on EC2..."
    ssh -i "$SSH_KEY" "ubuntu@$MOLTBOT_HOST" << EOF
sudo systemctl stop moltbot
sudo tar -xzf /tmp/${INSTANCE_NAME}-backup.tar.gz -C /home/$MOLTBOT_USER/
sudo chown -R $MOLTBOT_USER:$MOLTBOT_USER /home/$MOLTBOT_USER/.clawdbot /home/$MOLTBOT_USER/.gog /home/$MOLTBOT_USER/moltbot
sudo rm /tmp/${INSTANCE_NAME}-backup.tar.gz
sudo systemctl start moltbot
EOF

    if [ $? -ne 0 ]; then
        error "Restore failed"
        return 1
    fi

    success "Restore complete!"
    echo ""
    info "Service restarted. Check status:"
    info "  moltbot $INSTANCE_NAME ssh"
    info "  sudo systemctl status moltbot"
}

# SSH to instance
exec_ssh() {
    info "SSH to ${CYAN}$INSTANCE_NAME${NC}..."

    # Validate configuration
    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    if [[ "$MOLTBOT_HOST" == "UNKNOWN" ]]; then
        error "Instance IP not found"
        return 1
    fi

    ssh -i "$SSH_KEY" "ubuntu@$MOLTBOT_HOST"
}

# Show instance status
exec_status() {
    echo ""
    echo "${CYAN}=== Status for $INSTANCE_NAME ===${NC}"
    echo ""
    echo "Instance IP:    $MOLTBOT_HOST"
    echo "SSH Key:        $SSH_KEY"
    echo "Moltbot User:   $MOLTBOT_USER"
    echo "Gateway Port:   $MOLTBOT_PORT"
    echo "AWS Profile:    $AWS_PROFILE"
    echo "AWS Region:     $AWS_REGION"
    echo "Backup Dir:     $BACKUP_DIR"
    echo ""

    if [[ "$MOLTBOT_HOST" == "UNKNOWN" ]]; then
        warn "Instance not yet deployed or Terraform not initialized"
        echo ""
        info "To deploy:"
        info "  moltbot $INSTANCE_NAME terraform init"
        info "  moltbot $INSTANCE_NAME terraform apply"
        return 0
    fi

    # Validate SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        error "SSH key not found: $SSH_KEY"
        return 1
    fi

    info "Checking instance connectivity..."
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 "ubuntu@$MOLTBOT_HOST" "echo connected" 2>/dev/null; then
        success "Instance is reachable"
        echo ""

        info "Service status:"
        ssh -i "$SSH_KEY" "ubuntu@$MOLTBOT_HOST" "sudo systemctl status moltbot --no-pager" 2>&1 || true
    else
        error "Cannot connect to instance"
        error "Verify:"
        error "  1. Instance is running (check AWS console)"
        error "  2. Security group allows SSH from your IP"
        error "  3. SSH key has correct permissions (chmod 400)"
    fi
}
