# OpenClaw Onboarding Setup Guide

This guide covers the secure onboarding configuration for OpenClaw.

Throughout this guide, replace `{instance}` with your instance name (e.g., pepper, alfred, iris).

## Prerequisites

- OpenClaw installed (EC2 instance or Docker container)
- Telegram bot token (from @BotFather)
- API key for your AI provider (Gemini, OpenAI, etc.)

---

## Docker Onboarding

For Docker deployments, onboarding requires stopping the gateway first:

### Step 1: Stop the Gateway Container

```bash
cd docker
docker compose -f docker-compose.local.yml stop {instance}
```

### Step 2: Run Onboarding in a Setup Container

```bash
docker run --rm -it --name openclaw-{instance}-setup \
  -v openclaw_{instance}-config:/home/clawd/.openclaw \
  -v openclaw_{instance}-gogcli:/home/clawd/.config/gogcli \
  -v openclaw_{instance}-workspace:/home/clawd/openclaw \
  -e GOG_KEYRING_PASSWORD=openclaw-{instance} \
  --entrypoint bash \
  openclaw-local:latest
```

### Step 3: Run Onboard Inside the Container

```bash
openclaw onboard
```

Follow the wizard (see [Recommended Settings](#recommended-settings) below).

### Step 4: Exit and Start the Gateway

```bash
exit
docker compose -f docker-compose.local.yml up -d {instance}
```

### Step 5: Access the UI

Open http://127.0.0.1:18791 (or the port configured for your instance).

### Setting Up gog (Google Services)

After onboarding, configure gog for Gmail/Calendar access:

```bash
# Enter the running container
docker exec -it openclaw-{instance} bash

# Add Google credentials (requires client_secret.json from Google Cloud Console)
gog auth credentials /path/to/client_secret.json
gog auth add your@gmail.com --services gmail,calendar,drive

# The keyring password is auto-provided via GOG_KEYRING_PASSWORD env var
exit
```

---

## EC2 Onboarding

### Connect to Instance

```bash
./scripts/pepper {instance} ssh
```

## Install OpenClaw (if not already installed)

The Terraform user_data script installs OpenClaw automatically.

Check installation:
```bash
openclaw --version
```

If you need to install manually:
```bash
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-setup
```

## Switch to OpenClaw User

```bash
# Default user is "clawd" (configured in instance.yaml)
sudo -u clawd -i
```

## Run Onboarding

```bash
openclaw onboard
```

Select **Manual** when asked for setup type - this gives you control over security settings.

## Recommended Settings

### Workspace Path
```
/home/clawd/openclaw
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
| **Install daemon** | `No` | We use our pre-configured openclaw.service |

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

### For Docker Deployments

```bash
# Start the container
docker compose -f docker-compose.local.yml up -d {instance}

# Check logs
docker logs openclaw-{instance} -f

# Access UI at http://127.0.0.1:{port}
# (port is 18791 for iris, check your docker-compose for others)
```

### For EC2 Deployments

```bash
# Exit back to ubuntu user
exit

# Enable and start the service
sudo systemctl enable --now openclaw
sudo systemctl status openclaw
```

### Verify Service is Running

**Docker:**
```bash
docker ps --filter name=openclaw-{instance}
docker logs openclaw-{instance} -f
```

**EC2:**
```bash
sudo systemctl status openclaw
sudo journalctl -u openclaw -f
```

Expected output shows gateway listening on port 18789.

## Accessing the Gateway

**Never expose port 18789 to the internet.**

**Docker (local):**
- Access directly at http://127.0.0.1:{port}
- Port depends on your docker-compose config (e.g., 18791 for iris)

**EC2:**
- Use SSH tunnel: `./scripts/pepper {instance} connect`
- This creates the tunnel and opens http://127.0.0.1:18789 automatically.

## Telegram Bot Setup

### Create Bot with @BotFather

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Choose a name (e.g., "My OpenClaw Assistant")
4. Choose a username (must end in `bot`, e.g., `my_openclaw_bot`)
5. Copy the bot token

### Test the Bot

1. Search for your bot in Telegram
2. Send a message
3. Check the OpenClaw logs to confirm it's received

## Troubleshooting

### Bot not responding

**Docker:**
```bash
# Check container status
docker ps --filter name=openclaw-{instance}

# Check logs
docker logs openclaw-{instance} -f

# Restart container
docker compose -f docker-compose.local.yml restart {instance}
```

**EC2:**
```bash
# Check service status
sudo systemctl status openclaw

# Check logs
sudo journalctl -u openclaw -f

# Restart service
sudo systemctl restart openclaw
```

### Gateway not accessible

**Docker:**
1. Check container is running: `docker ps`
2. Check port mapping: `docker port openclaw-{instance}`
3. Check logs for errors: `docker logs openclaw-{instance}`

**EC2:**
1. Verify SSH tunnel is running
2. Check service is running: `sudo systemctl status openclaw`
3. Verify binding: `ss -tlnp | grep 18789`

### Update configuration

**Docker:**
```bash
docker exec -it openclaw-{instance} openclaw configure
```

**EC2:**
```bash
sudo -u clawd -i
openclaw configure
```

### gog Keyring Password Prompt

If gog prompts for a keyring password, the `GOG_KEYRING_PASSWORD` environment variable may not be set.

**Docker:** Check docker-compose includes:
```yaml
environment:
  - GOG_KEYRING_PASSWORD=openclaw-{instance}
```

Then restart: `docker compose -f docker-compose.local.yml up -d {instance}`

## Security Checklist

### All Deployments
- [ ] Gateway bound to `127.0.0.1` (not `0.0.0.0`)
- [ ] Telegram using Allowlist authorization
- [ ] Only your Telegram ID in allowlist
- [ ] API keys have minimal permissions

### EC2 Specific
- [ ] Gateway auth set to "Off (loopback only)"
- [ ] Tailscale disabled
- [ ] API key locked to EC2 IP
- [ ] UFW firewall enabled (port 18789 NOT open)
- [ ] Accessing gateway via SSH tunnel only

### Docker Specific
- [ ] Port mapping binds to `127.0.0.1` only (e.g., `127.0.0.1:18791:18789`)
- [ ] Volumes use named volumes (not bind mounts with secrets)
- [ ] GOG_KEYRING_PASSWORD set (for gog auto-unlock)
