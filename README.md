# Pepper - Personal AI Assistant

Pepper is a secure, self-hosted AI assistant built on [Moltbot](https://molt.bot) (formerly Clawdbot), running on a dedicated AWS EC2 instance with access to email, calendar, and messaging.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Personal Data                       │
│  Gmail (personal) ──forward──> Pepper's Gmail                │
│  Calendar (personal) ──subscribe──> Pepper's Calendar        │
│  WhatsApp ────────────> Telegram (via your account)          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               AWS EC2 Instance (af-south-1)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Moltbot (Pepper)                                     │  │
│  │  - Reads from Pepper's Gmail (via gog CLI)           │  │
│  │  - Queries Pepper's Calendar                          │  │
│  │  - Processes with Claude Opus 4.5                     │  │
│  │  - Gateway: 127.0.0.1:18789 (loopback only)          │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│  Security:                                                    │
│  ✓ Dedicated VPC, SSH-only access                           │
│  ✓ UFW firewall, fail2ban                                   │
│  ✓ IMDSv2, encrypted EBS                                    │
│  ✓ No public port 18789 exposure                           │
└─────────────────────────────────────────────────────────────┘
                              │
                  ┌───────────┴───────────┐
                  ▼                       ▼
         ┌────────────────┐      ┌──────────────┐
         │  Telegram Bot  │      │  Admin UI    │
         │  (allowlist)   │      │  (SSH tunnel)│
         └────────────────┘      └──────────────┘
                  │                       │
                  └───────────┬───────────┘
                              ▼
                      Your Phone/Laptop
```

## Security Model

### Data Isolation Strategy

**Problem**: Don't want to give AI direct access to personal Gmail/Calendar

**Solution**: Dedicated Google account for Pepper
- Pepper has her own `pepper@domain.com` Google account
- Your personal emails are **forwarded** to Pepper (selective via filters)
- Your calendars are **subscribed** by Pepper (read-only)
- If compromised: Delete Pepper's account, your data stays safe

### Network Security

- **EC2 Instance**: Isolated VPC, SSH-only access (your IP only)
- **Gateway**: Bound to `127.0.0.1` (not internet-accessible)
- **Admin UI**: Access via SSH tunnel only
- **Telegram**: Allowlist enforced (your user ID only)

### OAuth Scopes (Read-Only Where Possible)

For your personal accounts (if directly accessed):
- Gmail: `gmail.readonly` (no sending/deleting)
- Calendar: `calendar.events.readonly` (view only)

For Pepper's own account (dedicated):
- Full access (she owns the account)

### Disposable Infrastructure

- Instance can be destroyed and recreated via Terraform
- Backups restore configuration in minutes
- No persistent sensitive data on disk (OAuth tokens revokable)

---

## Quick Start

### Prerequisites

- AWS account with `noldor` profile configured
- Your IP address (for SSH restriction)
- Google account for Pepper
- Telegram account

### 1. Deploy Infrastructure

```bash
cd terraform/environments/prod

# Update terraform.tfvars with your IP
# allowed_ssh_cidr = "YOUR.IP.ADDRESS/32"

# Apply Terraform
AWS_PROFILE=noldor terraform init
AWS_PROFILE=noldor terraform apply
```

### 2. Connect to Instance

```bash
# SSH directly
ssh -i ~/.ssh/moltbot_key.pem ubuntu@13.247.25.37

# Or use the admin UI
./scripts/connectToAdmin.sh
```

### 3. Configure Integrations

Follow the setup guides:
- [Google Workspace Setup](docs/google-workspace-setup.md) - Gmail, Calendar, Drive
- [Moltbot Onboarding](docs/moltbot-onboarding-setup.md) - Initial configuration
- [Gemini API Setup](docs/gemini-api-key-setup.md) - Optional AI model

### 4. Test via Telegram

Message your bot:
```
What's on my calendar today?
Show me important emails
Draft a reply to that email from Sarah
```

---

## Documentation

- **[Google Workspace Setup](docs/google-workspace-setup.md)** - Configure Gmail, Calendar, Drive access
- **[Moltbot Onboarding](docs/moltbot-onboarding-setup.md)** - Initial bot configuration
- **[Gemini API Setup](docs/gemini-api-key-setup.md)** - Alternative AI model configuration
- **[Backup & Restore Guide](docs/backup-restore-guide.md)** - Disaster recovery procedures
- **[Terraform README](terraform/README.md)** - Infrastructure details

---

## Daily Usage

### Access Admin UI

```bash
./scripts/connectToAdmin.sh
# Opens http://127.0.0.1:18789 in your browser
```

### SSH to Instance

```bash
ssh -i ~/.ssh/moltbot_key.pem ubuntu@13.247.25.37

# Switch to Pepper's user
sudo -u clawd -i
```

### Check Service Status

```bash
sudo systemctl status moltbot
sudo journalctl -u moltbot -f
```

### Restart Service

```bash
sudo systemctl restart moltbot
```

---

## Backup & Recovery

### Create Backup

```bash
./scripts/backup-pepper.sh
# Saves to ~/.pepper-backups/YYYYMMDD-HHMMSS/
```

### Restore After Instance Recreation

```bash
# 1. Destroy and recreate
cd terraform/environments/prod
AWS_PROFILE=noldor terraform destroy
AWS_PROFILE=noldor terraform apply

# 2. Restore from backup
./scripts/restore-pepper.sh ~/.pepper-backups/latest/pepper-backup.tar.gz
```

See [Backup & Restore Guide](docs/backup-restore-guide.md) for details.

---

## Terraform Infrastructure

All infrastructure is defined in `terraform/`:

```
terraform/
├── environments/prod/          # Production environment
│   ├── main.tf                 # Root module
│   ├── terraform.tfvars.example
│   └── variables.tf
└── modules/moltbot/            # Reusable module
    ├── vpc.tf                  # Dedicated VPC
    ├── security.tf             # Security groups, ACLs
    ├── ec2.tf                  # EC2 instance
    ├── iam.tf                  # IAM roles
    └── user_data/init.sh.tftpl # Bootstrap script
```

**Resources created:**
- VPC with public subnet
- Security group (SSH only from your IP)
- EC2 t3.small with Ubuntu 22.04
- EBS encryption, IMDSv2
- SSH key pair
- IAM role for CloudWatch/SSM
- VPC Flow Logs

See [terraform/README.md](terraform/README.md) for details.

---

## Security Considerations

### What's Protected

✅ Gateway not exposed to internet
✅ SSH restricted to your IP only
✅ Telegram bot allowlist enforced
✅ OAuth tokens isolated to Pepper's account
✅ EBS encryption, IMDSv2 enabled
✅ Firewall (UFW) + fail2ban configured

### What to Monitor

⚠️ **Supply chain risk**: Moltbot is open source but had [recent security issues](https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns/)
⚠️ **Network traffic**: Monitor outbound connections for unexpected domains
⚠️ **OAuth usage**: Check Google Cloud Console for API usage anomalies
⚠️ **Telegram 2FA**: Enable on your account (bot allowlist is only defense)

### Hardening Options

```bash
# Monitor outbound traffic
sudo journalctl -f | grep OUTBOUND

# Restrict outbound (allow only essential)
sudo ufw default deny outgoing
sudo ufw allow out 443    # HTTPS
sudo ufw allow out 53     # DNS

# Monitor DNS queries
sudo apt install dnstop
sudo dnstop -l 3 eth0
```

See [docs/google-workspace-setup.md](docs/google-workspace-setup.md) for more.

---

## Cost Estimate

**Monthly AWS costs** (af-south-1 region):
- EC2 t3.small: ~$15/month
- EBS 30GB encrypted: ~$3/month
- Data transfer: ~$1/month
- **Total: ~$19/month**

**Other costs**:
- Anthropic Claude API: Pay-as-you-go (Opus 4.5: $15/$75 per million tokens)
- Google Workspace APIs: Free tier (10k requests/day)

---

## Troubleshooting

### Service not starting

```bash
sudo journalctl -u moltbot -n 50
sudo systemctl status moltbot
```

### Gateway not accessible

```bash
# Check if listening on loopback
sudo ss -tlnp | grep 18789

# Should show: 127.0.0.1:18789

# Test health
curl http://127.0.0.1:18789/health
```

### Telegram bot not responding

```bash
# Check allowlist in config
sudo -u clawd cat ~/.clawdbot/clawdbot.json | grep -A5 telegram

# Verify your user ID is in allowFrom array
```

### OAuth errors

```bash
# Re-authenticate
sudo -u clawd -i
gog auth list
gog auth add pepper@domain.com
```

---

## Development

### Local Testing

```bash
# Run Terraform plan
cd terraform/environments/prod
AWS_PROFILE=noldor terraform plan

# Validate changes
AWS_PROFILE=noldor terraform validate
```

### Update User Data Script

After editing `terraform/modules/moltbot/user_data/init.sh.tftpl`:

```bash
# Recreate instance with new user_data
AWS_PROFILE=noldor terraform apply -replace=module.moltbot.aws_instance.moltbot
```

---

## Useful Commands

```bash
# Connect to admin UI
./scripts/connectToAdmin.sh

# SSH to instance
ssh -i ~/.ssh/moltbot_key.pem ubuntu@13.247.25.37

# Backup Pepper's data
./scripts/backup-pepper.sh

# Restore from backup
./scripts/restore-pepper.sh ~/.pepper-backups/latest/pepper-backup.tar.gz

# View Terraform outputs
cd terraform/environments/prod
AWS_PROFILE=noldor terraform output

# Destroy everything (careful!)
AWS_PROFILE=noldor terraform destroy
```

---

## Project Structure

```
.
├── README.md                           # This file
├── CLAUDE.md                          # Project context for Claude
├── scripts/
│   ├── connectToAdmin.sh              # SSH tunnel + open browser
│   ├── backup-pepper.sh               # Backup script
│   └── restore-pepper.sh              # Restore script
├── docs/
│   ├── google-workspace-setup.md      # Gmail/Calendar setup
│   ├── moltbot-onboarding-setup.md    # Initial configuration
│   ├── gemini-api-key-setup.md        # Gemini API setup
│   └── backup-restore-guide.md        # Disaster recovery
└── terraform/
    ├── README.md                       # Infrastructure docs
    ├── environments/prod/              # Production config
    └── modules/moltbot/                # Reusable module
```

---

## Resources

- **Moltbot Docs**: https://docs.molt.bot
- **Anthropic Claude**: https://console.anthropic.com
- **Google Cloud Console**: https://console.cloud.google.com
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws

---

## License

Personal project - not licensed for distribution.

---

## Support

For issues with:
- **Infrastructure**: Check Terraform logs, AWS Console
- **Moltbot**: See https://docs.molt.bot or https://github.com/moltbot/clawdbot/issues
- **This setup**: Refer to docs/ folder

---

## Changelog

- **2026-01-28**: Initial setup with Terraform, Google Workspace integration, backup scripts
