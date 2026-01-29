# Moltbot Onboarding Setup Guide

This guide covers the secure onboarding configuration for moltbot on your EC2 instance.

Throughout this guide, replace `{instance}` with your instance name (e.g., pepper, alfred, jarvis).

## Prerequisites

- EC2 instance running with moltbot installed
- SSH access to the instance
- Telegram bot token (from @BotFather)
- Gemini API key (see [gemini-api-key-setup.md](./gemini-api-key-setup.md))

## Connect to Instance

```bash
./scripts/moltbot {instance} ssh
```

## Install Moltbot (if not already installed)

```bash
sudo npm install -g moltbot@latest
```

## Switch to Moltbot User

```bash
# Default user is "clawd" (configured in instance.yaml)
sudo -u clawd -i
```

## Run Onboarding

```bash
moltbot onboard
```

Select **Manual** when asked for setup type - this gives you control over security settings.

## Recommended Settings

### Workspace Path
```
/home/clawd/moltbot
```

### Gateway Configuration

| Setting | Value | Reason |
|---------|-------|--------|
| **Gateway host** | `127.0.0.1` | Loopback only - not accessible from network |
| **Gateway port** | `18789` | Default port |
| **Gateway auth** | `Off (loopback only)` | SSH tunnel provides authentication |
| **Tailscale** | `Off` | Using SSH tunnel instead |

### AI Provider

| Setting | Value |
|---------|-------|
| **Provider** | Gemini (or your choice) |
| **API Key** | Your locked-down Gemini key |

### Telegram Configuration

| Setting | Value | Reason |
|---------|-------|--------|
| **Bot Token** | From @BotFather | Your Telegram bot |
| **Authorization** | `Allowlist` | More secure for personal use |
| **Telegram User ID** | Your ID | Only you can use the bot |

### Other Settings

| Setting | Value | Reason |
|---------|-------|--------|
| **Install daemon** | `No` | We have a pre-configured systemd service |

## Authorization: Allowlist vs DM Pairing

### Allowlist (Recommended for Personal Use)
- Only specified Telegram user IDs can interact
- Unknown users are blocked immediately
- No approval workflow needed
- More secure, less flexible

### DM Pairing
- Anyone can request pairing
- You manually approve each request
- More flexible for adding users
- Less secure (requests can be initiated)

**For a personal bot, use Allowlist.**

## Getting Your Telegram User ID

1. Message @userinfobot on Telegram
2. It will reply with your user ID
3. Use this ID in the allowlist

## After Onboarding

### Start the Moltbot Service

```bash
# Exit back to ubuntu user
exit

# Enable and start the service
sudo systemctl enable --now moltbot
sudo systemctl status moltbot
```

### Verify Service is Running

```bash
sudo systemctl status moltbot
```

Expected output: `Active: active (running)`

### Check Logs

```bash
sudo journalctl -u moltbot -f
```

## Accessing the Gateway

**Never expose port 18789 to the internet.**

From your local machine, use the wrapper to create an SSH tunnel and open the browser:

```bash
./scripts/moltbot {instance} connect
```

This creates the tunnel and opens http://127.0.0.1:18789 automatically.

## Telegram Bot Setup

### Create Bot with @BotFather

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Choose a name (e.g., "My Moltbot Assistant")
4. Choose a username (must end in `bot`, e.g., `my_moltbot_bot`)
5. Copy the bot token

### Test the Bot

1. Search for your bot in Telegram
2. Send a message
3. Check the moltbot logs to confirm it's received

## Troubleshooting

### Bot not responding
```bash
# Check service status
sudo systemctl status moltbot

# Check logs
sudo journalctl -u moltbot -f

# Restart service
sudo systemctl restart moltbot
```

### Gateway not accessible
1. Verify SSH tunnel is running
2. Check service is running: `sudo systemctl status moltbot`
3. Verify binding: `ss -tlnp | grep 18789`

### Update configuration
```bash
sudo -u clawd -i
moltbot configure
```

## Security Checklist

- [ ] Gateway bound to `127.0.0.1` (not `0.0.0.0`)
- [ ] Gateway auth set to "Off (loopback only)"
- [ ] Tailscale disabled
- [ ] Telegram using Allowlist authorization
- [ ] Only your Telegram ID in allowlist
- [ ] API key locked to EC2 IP
- [ ] UFW firewall enabled (port 18789 NOT open)
- [ ] Accessing gateway via SSH tunnel only
