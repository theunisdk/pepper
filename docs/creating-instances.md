# Creating Multiple OpenClaw Instances

This guide shows how to create and manage multiple named OpenClaw instances (e.g., "pepper", "alfred", "jarvis").

## Overview

Each instance is:
- Completely isolated (separate AWS infrastructure, SSH keys, backups)
- Independently deployable and destroyable
- Configured via its own `instance.yaml` and `terraform.tfvars`

## Quick Start: Create a New Instance

```bash
# 1. Create instance named "alfred"
./scripts/create-instance.sh alfred

# 2. Edit configuration
nano instances/alfred/terraform.tfvars
# Update: allowed_ssh_cidr = "YOUR_IP/32"

# 3. Deploy
./scripts/pepper alfred terraform init
./scripts/pepper alfred terraform apply

# 4. Connect and configure
./scripts/pepper alfred ssh
sudo -u clawd -i
openclaw onboard

# 5. Use
./scripts/pepper alfred connect
```

## Instance Management Commands

All instance operations use the `pepper` wrapper:

```bash
# Deploy instance
./scripts/pepper {name} terraform init
./scripts/pepper {name} terraform apply

# Connect to admin UI (opens browser with SSH tunnel)
./scripts/pepper {name} connect

# Backup
./scripts/pepper {name} backup

# Restore
./scripts/pepper {name} restore [backup-file]

# SSH
./scripts/pepper {name} ssh

# Status
./scripts/pepper {name} status

# Destroy
./scripts/pepper {name} terraform destroy
```

## Directory Structure Per Instance

```
instances/alfred/
├── instance.yaml          # Instance configuration
├── main.tf                # Terraform configuration (generated)
├── variables.tf           # Terraform variables (generated)
├── terraform.tfvars       # Your values (gitignored)
├── .terraform/            # Terraform state (gitignored)
└── .gitignore
```

## Configuration: instance.yaml

Each instance has an `instance.yaml` that defines:
- Instance name and metadata
- AWS region and profile
- Instance type and sizing
- SSH key paths (unique per instance)
- Backup locations
- Network configuration

Example:
```yaml
name: alfred
display_name: Alfred

aws:
  profile: noldor
  region: af-south-1

instance:
  type: t3.small
  volume_size: 30

openclaw:
  user: clawd
  gateway_port: 18789

ssh:
  key_name: alfred_key
  key_path: ~/.ssh/alfred_key.pem
  public_key_path: ~/.ssh/alfred_key.pub

network:
  allowed_ssh_cidr: "YOUR_IP/32"
  vpc_cidr: "10.101.0.0/16"  # Different from other instances!
  subnet_cidr: "10.101.1.0/24"

paths:
  backup_dir: ~/.alfred-backups

tags:
  Owner: your-name
  Project: openclaw-alfred
```

## Network Isolation

Each instance should use a unique VPC CIDR to avoid conflicts:

| Instance | VPC CIDR | Subnet CIDR |
|----------|----------|-------------|
| pepper | 10.100.0.0/16 | 10.100.1.0/24 |
| alfred | 10.101.0.0/16 | 10.101.1.0/24 |
| jarvis | 10.102.0.0/16 | 10.102.1.0/24 |

## SSH Key Isolation

Each instance generates its own SSH key pair:
- `~/.ssh/pepper_key.pem`
- `~/.ssh/alfred_key.pem`
- `~/.ssh/jarvis_key.pem`

Keys are never shared between instances for security isolation.

## Backup Isolation

Backups are stored in separate directories:
- `~/.pepper-backups/`
- `~/.alfred-backups/`
- `~/.jarvis-backups/`

This prevents accidental restore to the wrong instance.

## Working with Multiple Instances

The `pepper` wrapper handles context switching:

```bash
# Work on pepper
./scripts/pepper pepper status
./scripts/pepper pepper backup

# Work on alfred
./scripts/pepper alfred status
./scripts/pepper alfred backup

# Work on jarvis
./scripts/pepper jarvis terraform apply
```

## Example: Complete New Instance Setup

```bash
# 1. Create instance
./scripts/create-instance.sh jarvis

# Output:
# ✓ Instance created: jarvis
#
# Next steps:
#   1. Edit configuration:
#      nano instances/jarvis/terraform.tfvars
#      → Set your IP address in allowed_ssh_cidr
#
#   2. Initialize Terraform:
#      ./scripts/pepper jarvis terraform init
#
#   3. Deploy infrastructure:
#      ./scripts/pepper jarvis terraform apply
#
#   4. Connect and configure:
#      ./scripts/pepper jarvis ssh
#      sudo -u clawd -i
#      openclaw onboard
#
#   5. Access admin UI:
#      ./scripts/pepper jarvis connect

# 2. Edit configuration
nano instances/jarvis/terraform.tfvars
# Update:
#   allowed_ssh_cidr = "203.0.113.50/32"
#   vpc_cidr = "10.102.0.0/16"
#   public_subnet_cidr = "10.102.1.0/24"

# 3. Deploy
./scripts/pepper jarvis terraform init
./scripts/pepper jarvis terraform apply

# Terraform will output:
# Apply complete! Resources: 21 added, 0 changed, 0 destroyed.
#
# Outputs:
# instance_public_ip = "13.247.99.123"
# ssh_connection_command = "ssh -i ~/.ssh/jarvis_key.pem ubuntu@13.247.99.123"

# 4. SSH and configure openclaw
./scripts/pepper jarvis ssh
# On EC2:
sudo -u clawd -i
openclaw onboard
# ... follow onboarding wizard ...
exit

# 5. Enable service
sudo systemctl enable --now openclaw
exit

# 6. Connect to admin UI
./scripts/pepper jarvis connect
# Opens http://127.0.0.1:18789 in browser

# 7. Backup
./scripts/pepper jarvis backup
# Saved to ~/.jarvis-backups/20260129-140000/jarvis-backup.tar.gz
```

## Instance States

Check instance status:

```bash
./scripts/pepper pepper status
```

Output shows:
- Instance IP
- SSH key path
- Service status
- Connectivity

## Troubleshooting

### Instance not found

```
Error: Instance configuration not found: instances/alfred/instance.yaml
```

**Solution**: Create the instance first with `./scripts/create-instance.sh alfred`

### IP shows "UNKNOWN"

```
Instance IP:    UNKNOWN
```

**Solution**: Terraform not yet applied. Run:
```bash
./scripts/pepper {instance} terraform init
./scripts/pepper {instance} terraform apply
```

### Cannot connect to instance

```
Error: Cannot connect to instance
```

**Solutions**:
1. Check instance is running (AWS console)
2. Verify security group allows SSH from your IP
3. Check SSH key permissions: `chmod 400 ~/.ssh/{instance}_key.pem`

### Wrong IP address

If your IP changed, update terraform.tfvars:

```bash
nano instances/{instance}/terraform.tfvars
# Update allowed_ssh_cidr = "NEW_IP/32"

./scripts/pepper {instance} terraform apply
```

## Destroying Instances

To completely remove an instance:

```bash
# 1. Backup first (optional but recommended)
./scripts/pepper {instance} backup

# 2. Destroy infrastructure
./scripts/pepper {instance} terraform destroy

# 3. Remove instance directory (optional)
rm -rf instances/{instance}/
```

## Cost Management

Each instance costs approximately:
- EC2 t3.small: ~$15/month
- EBS 30GB: ~$3/month
- Data transfer: ~$1/month
- **Total per instance: ~$19/month**

Running 3 instances (pepper, alfred, jarvis) = ~$57/month

You can reduce costs by:
- Using smaller instance types (t3.micro for testing)
- Stopping instances when not in use (EC2 charges only when running)
- Using smaller EBS volumes

## Security Notes

1. **SSH Key Isolation**: Each instance has its own key - never shared
2. **Network Isolation**: Separate VPCs prevent cross-instance access
3. **State Isolation**: Terraform state is per-instance (no conflicts)
4. **Backup Isolation**: Separate directories prevent restoration errors
5. **Gateway Security**: Each gateway binds to 127.0.0.1 (SSH tunnel required)

## Best Practices

1. **Naming**: Use lowercase names with hyphens: `my-bot`, not `MyBot`
2. **VPC CIDRs**: Use sequential ranges to avoid conflicts
3. **Backups**: Run regular backups for production instances
4. **Testing**: Create test instances before changes
5. **Tags**: Update `additional_tags` in terraform.tfvars for organization
6. **Documentation**: Keep notes on what each instance is used for

## Migration from Single Instance

If you have an existing single instance setup, it's already migrated! The `pepper` instance in this repo is the original setup, now managed via the multi-instance framework.

To verify:
```bash
./scripts/pepper pepper status
```

All old commands have been replaced:
```bash
# OLD (removed)
./scripts/backup-pepper.sh
./scripts/restore-pepper.sh
./scripts/connectToAdmin.sh

# NEW (use these)
./scripts/pepper pepper backup
./scripts/pepper pepper restore
./scripts/pepper pepper connect
```

## Advanced: Instance Templates

You can customize `instances/instance.yaml.example` as a template for your organization's standard configuration.

Example use cases:
- Development instances (smaller, cheaper)
- Production instances (larger, monitored)
- Testing instances (disposable, minimal config)

## Getting Help

```bash
# Show usage
./scripts/pepper help

# List available instances
ls -1 instances/ | grep -v ".example"

# Check instance status
./scripts/pepper {instance} status
```

For issues:
- Check instance status first
- Review Terraform logs
- Verify security group and SSH key permissions
- Check AWS Console for instance state
