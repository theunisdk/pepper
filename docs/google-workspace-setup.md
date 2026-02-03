# Google Workspace Setup for OpenClaw

This guide shows how to set up Gmail, Calendar, and Drive access for your OpenClaw instance using a dedicated Google account.

Throughout this guide, replace `{instance}` with your instance name (e.g., pepper, alfred, jarvis).

## Architecture

```
Your Personal Gmail → Forward rules → Bot's Gmail
                                      ↓
                                   OpenClaw reads/processes
                                      ↓
                                   Responds via Telegram

Your Calendar → Subscribe link → Bot's Calendar (read-only view)
```

**Security Benefits:**
- Your bot has its own dedicated Google account
- You control what it sees via forwarding rules
- If compromised, delete the bot's account (your data stays safe)
- OAuth tokens are isolated to the bot's account

---

## Part 1: Create Bot's Google Account

1. Go to https://accounts.google.com/signup
2. Create new account: `{instance}@yourdomain.com` (or use Gmail)
3. Enable 2FA (recommended)
4. This becomes your bot's workspace account

---

## Part 2: Google Cloud Console Setup

### Step 1: Create Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click **Select a project** → **New Project**
3. Name: `{Instance} OpenClaw` (e.g., "Pepper Moltbot")
4. Click **Create**

### Step 2: Enable APIs

1. Go to **APIs & Services → Library**
2. Search and enable each:
   - **Gmail API**
   - **Google Calendar API**
   - **Google Drive API**

### Step 3: Configure OAuth Consent Screen

1. Go to **APIs & Services → OAuth consent screen**
2. Select **External** user type → **Create**
3. Fill in:
   - App name: `{Instance} OpenClaw` (e.g., "Pepper Moltbot")
   - User support email: your email
   - Developer contact: your email
4. Click **Save and Continue**

### Step 4: Add Scopes

1. Click **Add or Remove Scopes**
2. Add these scopes:
   ```
   https://mail.google.com/
   https://www.googleapis.com/auth/calendar
   https://www.googleapis.com/auth/drive
   ```
3. Click **Update** → **Save and Continue**

### Step 5: Add Test Users

1. Click **Add Users**
2. Add your bot's email: `{instance}@yourdomain.com`
3. Click **Save and Continue**

### Step 6: Create OAuth Credentials

1. Go to **APIs & Services → Credentials**
2. Click **Create Credentials → OAuth client ID**
3. Application type: **Desktop app**
4. Name: `{Instance} Desktop Client` (e.g., "Pepper Desktop Client")
5. Click **Create**
6. **Download JSON** (save as `{instance}-credentials.json`)
7. Keep this file secure - you'll upload it to EC2

### Step 7: Set API Restrictions (Optional Security)

1. Click on the created OAuth client ID
2. Under **API restrictions**, select **Restrict key**
3. Choose only:
   - Gmail API
   - Calendar API
   - Drive API
4. Click **Save**

---

## Part 3: Install gog CLI on EC2

SSH to your instance and install the Google Workspace CLI:

```bash
# Connect to EC2
./scripts/pepper {instance} ssh

# Switch to clawd user (or your configured openclaw_user)
sudo -u clawd -i

# Install gog CLI globally
npm install -g @go-on-git/gog

# Verify installation
gog --version
```

---

## Part 4: Configure OAuth on EC2

### Upload credentials to EC2

From your local machine:

```bash
# Get instance IP
INSTANCE_IP=$(./scripts/pepper {instance} terraform output -raw instance_public_ip)

# Upload the JSON credentials file
scp -i ~/.ssh/{instance}_key.pem ~/Downloads/{instance}-credentials.json ubuntu@$INSTANCE_IP:/tmp/
```

### Authenticate gog CLI

On EC2 as clawd user:

```bash
# Store OAuth credentials
gog auth credentials /tmp/{instance}-credentials.json

# Add your bot's Google account (opens browser for OAuth)
gog auth add {instance}@yourdomain.com

# Follow the browser prompt:
# 1. Sign in as {instance}@yourdomain.com
# 2. Grant access to Gmail, Calendar, Drive
# 3. Copy the authorization code back to terminal

# Test the connection
gog gmail labels list
gog calendar list
gog drive list
```

### Configure OpenClaw

Add to `~/.clawdbot/.env`:

```bash
GOG_ACCOUNT={instance}@yourdomain.com
```

Or edit `~/.clawdbot/clawdbot.json`:

```json
{
  "skills": {
    "entries": {
      "google-workspace": {
        "enabled": true,
        "config": {
          "account": "{instance}@yourdomain.com"
        }
      }
    }
  }
}
```

### Restart OpenClaw

```bash
# Exit clawd user
exit

# Restart service
sudo systemctl restart openclaw
sudo systemctl status openclaw
```

---

## Part 5: Set Up Gmail Forwarding

Forward selected emails from your personal account to your bot:

### From Your Gmail

1. Go to [Gmail Settings → Forwarding and POP/IMAP](https://mail.google.com/mail/u/0/#settings/fwdandpop)
2. Click **Add a forwarding address**
3. Enter: `{instance}@yourdomain.com`
4. Gmail sends a confirmation code to your bot's account
5. Check your bot's inbox and confirm

### Create Filters (Selective Forwarding)

Instead of forwarding everything, create filters:

1. Go to **Settings → Filters and Blocked Addresses**
2. Click **Create a new filter**
3. Example filters:
   - **Important emails**: `is:important` → Forward to bot
   - **Specific senders**: `from:boss@work.com` → Forward to bot
   - **Labeled emails**: `label:{instance}` → Forward to bot
4. Check **Forward it to** → Select `{instance}@yourdomain.com`
5. Click **Create filter**

**Recommended approach**: Create a label with your instance name and manually label emails you want the bot to see.

---

## Part 6: Set Up Calendar Subscriptions

Share your calendars with your bot (read-only):

### From Your Google Calendar

1. Go to [Google Calendar](https://calendar.google.com)
2. Click on your calendar → **Settings and sharing**
3. Scroll to **Share with specific people**
4. Click **Add people**
5. Enter: `{instance}@yourdomain.com`
6. Permission: **See all event details**
7. Click **Send**

### Multiple Calendars

Repeat for each calendar you want your bot to access:
- Work calendar
- Personal calendar
- Family calendar

Your bot will see these as read-only subscriptions in its account.

---

## Part 7: Test Integration

Via Telegram or admin UI, test these commands:

### Gmail
```
Show me my recent emails
What's in my inbox?
Any important emails from today?
```

### Calendar
```
What's on my calendar today?
Do I have any meetings tomorrow?
When is my next appointment?
```

### Drive
```
Create a note about our conversation
Save this to Drive
List my recent files
```

---

## Security Notes

1. **OAuth Token Storage**: Tokens are stored in `~/.clawdbot/` and `~/.gog/` - never commit these
2. **Revoke Access**: Go to [Google Account Permissions](https://myaccount.google.com/permissions) to revoke if needed
3. **IP Restriction**: Optionally restrict API keys to your EC2 instance IP (get via `./scripts/pepper {instance} terraform output instance_public_ip`)
4. **Rotation**: Periodically delete and recreate OAuth tokens (every 6-12 months)
5. **Monitoring**: Check your bot's Gmail regularly for unexpected access

---

## Backup OAuth Credentials

See [backup-restore-guide.md](backup-restore-guide.md) for backing up:
- `~/.clawdbot/` (includes credentials)
- `~/.gog/` (OAuth tokens)
- `/tmp/{instance}-credentials.json` (keep local copy too)

---

## Troubleshooting

### "Access blocked: This app's request is invalid"
- App is still in testing mode
- Make sure your bot's email is added as a test user in Google Cloud Console

### "gog: command not found"
- Install globally: `npm install -g @go-on-git/gog`
- Check PATH: `echo $PATH | grep npm`

### "Authentication failed"
- Delete tokens: `rm -rf ~/.gog/`
- Re-authenticate: `gog auth add {instance}@yourdomain.com`

### Rate limiting
- Google has API quotas (usually 10,000 requests/day for Gmail)
- Monitor usage: [Google Cloud Console → APIs & Services → Dashboard](https://console.cloud.google.com/apis/dashboard)

---

## Alternative: Multiple Personal Accounts

If you want Pepper to access multiple personal accounts:

```bash
# Add multiple accounts
gog auth add personal@gmail.com
gog auth add work@company.com

# Configure in OpenClaw
GOG_ACCOUNTS=personal@gmail.com,work@company.com
```

Each requires separate OAuth authorization with read-only scopes:
- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/calendar.events.readonly`
