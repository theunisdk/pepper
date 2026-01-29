#!/bin/bash
# Configuration loading for instances

# Parse simple YAML values (key: value format)
parse_yaml() {
    local file="$1"
    local key="$2"

    # Handle nested keys like "aws.profile"
    if [[ "$key" == *.* ]]; then
        # For nested keys, look for the parent section first
        local parent="${key%%.*}"
        local child="${key##*.}"

        # Extract the value from under the parent section
        awk -v parent="$parent:" -v child="$child:" '
            $0 ~ "^" parent {in_section=1; next}
            in_section && $1 == child {
                gsub(/^[[:space:]]+/, "");
                sub(/^[^:]+:[[:space:]]*/, "");
                gsub(/"/, "");
                print;
                exit
            }
            in_section && /^[a-z]/ {in_section=0}
        ' "$file"
    else
        # For top-level keys
        awk -v key="$key:" '$1 == key {
            gsub(/^[[:space:]]+/, "");
            sub(/^[^:]+:[[:space:]]*/, "");
            gsub(/"/, "");
            print;
            exit
        }' "$file"
    fi
}

# Get instance IP from Terraform output
get_instance_ip() {
    local instance_name="$1"
    local tf_dir="$PROJECT_ROOT/instances/$instance_name"

    if [[ ! -d "$tf_dir/.terraform" ]]; then
        echo "UNKNOWN"
        return 1
    fi

    cd "$tf_dir" 2>/dev/null || return 1
    terraform output -raw instance_public_ip 2>/dev/null || echo "UNKNOWN"
}

# Load instance configuration
load_instance_config() {
    local instance_name="$1"
    local config_file="$PROJECT_ROOT/instances/$instance_name/instance.yaml"

    if [[ ! -f "$config_file" ]]; then
        error "Instance configuration not found: $config_file"
        error ""
        error "Available instances:"
        if ls -1 "$PROJECT_ROOT/instances" 2>/dev/null | grep -v ".example" >/dev/null; then
            ls -1 "$PROJECT_ROOT/instances" | grep -v ".example" | sed 's/^/  /'
        else
            echo "  None"
        fi
        error ""
        error "To create a new instance:"
        error "  $PROJECT_ROOT/scripts/create-instance.sh $instance_name"
        return 1
    fi

    # Export environment variables for use by other scripts
    export INSTANCE_NAME="$instance_name"
    export INSTANCE_DIR="$PROJECT_ROOT/instances/$instance_name"
    export INSTANCE_CONFIG="$config_file"

    # Parse configuration values
    export MOLTBOT_USER=$(parse_yaml "$config_file" "moltbot.user")
    export MOLTBOT_PORT=$(parse_yaml "$config_file" "moltbot.gateway_port")
    export AWS_PROFILE=$(parse_yaml "$config_file" "aws.profile")
    export AWS_REGION=$(parse_yaml "$config_file" "aws.region")

    # Parse SSH key paths and expand tilde
    local ssh_key=$(parse_yaml "$config_file" "ssh.key_path")
    export SSH_KEY="${ssh_key/#\~/$HOME}"

    local ssh_pubkey=$(parse_yaml "$config_file" "ssh.public_key_path")
    export SSH_PUBKEY="${ssh_pubkey/#\~/$HOME}"

    # Parse backup directory and replace {name} placeholder
    local backup_dir=$(parse_yaml "$config_file" "paths.backup_dir")
    backup_dir="${backup_dir//\{name\}/$instance_name}"
    export BACKUP_DIR="${backup_dir/#\~/$HOME}"

    # Get instance IP
    export MOLTBOT_HOST=$(get_instance_ip "$instance_name")

    info "Loaded configuration for instance: ${CYAN}$instance_name${NC}"

    return 0
}
