# Google Workspace Setup for Pepper

This guide shows how to set up Gmail, Calendar, and Drive access for Pepper using a dedicated Google account.

## Architecture

```
Your Personal Gmail → Forward rules → Pepper's Gmail
                                      ↓
                                   Moltbot reads/processes
                                      ↓
                                   Responds via Telegram

Your Calendar → Subscribe link → Pepper's Calendar (read-only view)
```

**Security Benefits:**
- Pepper has her own dedicated Google account
- You control what she sees via forwarding rules
- If compromised, delete Pepper's account (your data stays safe)
- OAuth tokens are isolated to Pepper's account

---

## Part 1: Create Pepper's Google Account

1. Go to https://accounts.google.com/signup
2. Create new account: `pepper@yourdomain.com` (or use Gmail)
3. Enable 2FA (recommended)
4. This becomes Pepper's workspace account

---

## Part 2: Google Cloud Console Setup

### Step 1: Create Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Click **Select a project** → **New Project**
3. Name: `Pepper Moltbot`
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
   - App name: `Pepper Moltbot`
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
2. Add Pepper's email: `pepper@yourdomain.com`
3. Click **Save and Continue**

### Step 6: Create OAuth Credentials

1. Go to **APIs & Services → Credentials**
2. Click **Create Credentials → OAuth client ID**
3. Application type: **Desktop app**
4. Name: `Pepper Desktop Client`
5. Click **Create**
6. **Download JSON** (save as `pepper-credentials.json`)
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
ssh -i ~/.ssh/moltbot_key.pem ubuntu@13.247.25.37

# Switch to clawd user
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
# Upload the JSON credentials file
scp -i ~/.ssh/moltbot_key.pem ~/Downloads/pepper-credentials.json ubuntu@13.247.25.37:/tmp/
```

### Authenticate gog CLI

On EC2 as clawd user:

```bash
# Store OAuth credentials
gog auth credentials /tmp/pepper-credentials.json

# Add Pepper's Google account (opens browser for OAuth)
gog auth add pepper@yourdomain.com

# Follow the browser prompt:
# 1. Sign in as pepper@yourdomain.com
# 2. Grant access to Gmail, Calendar, Drive
# 3. Copy the authorization code back to terminal

# Test the connection
gog gmail labels list
gog calendar list
gog drive list
```

### Configure Moltbot

Add to `~/.clawdbot/.env`:

```bash
GOG_ACCOUNT=pepper@yourdomain.com
```

Or edit `~/.clawdbot/clawdbot.json`:

```json
{
  "skills": {
    "entries": {
      "google-workspace": {
        "enabled": true,
        "config": {
          "account": "pepper@yourdomain.com"
        }
      }
    }
  }
}
```

### Restart Moltbot

```bash
# Exit clawd user
exit

# Restart service
sudo systemctl restart moltbot
sudo systemctl status moltbot
```

---

## Part 5: Set Up Gmail Forwarding

Forward selected emails from your personal account to Pepper:

### From Your Gmail

1. Go to [Gmail Settings → Forwarding and POP/IMAP](https://mail.google.com/mail/u/0/#settings/fwdandpop)
2. Click **Add a forwarding address**
3. Enter: `pepper@yourdomain.com`
4. Gmail sends a confirmation code to Pepper's account
5. Check Pepper's inbox and confirm

### Create Filters (Selective Forwarding)

Instead of forwarding everything, create filters:

1. Go to **Settings → Filters and Blocked Addresses**
2. Click **Create a new filter**
3. Example filters:
   - **Important emails**: `is:important` → Forward to Pepper
   - **Specific senders**: `from:boss@work.com` → Forward to Pepper
   - **Labeled emails**: `label:pepper` → Forward to Pepper
4. Check **Forward it to** → Select `pepper@yourdomain.com`
5. Click **Create filter**

**Recommended approach**: Create a label "pepper" and manually label emails you want Pepper to see.

---

## Part 6: Set Up Calendar Subscriptions

Share your calendars with Pepper (read-only):

### From Your Google Calendar

1. Go to [Google Calendar](https://calendar.google.com)
2. Click on your calendar → **Settings and sharing**
3. Scroll to **Share with specific people**
4. Click **Add people**
5. Enter: `pepper@yourdomain.com`
6. Permission: **See all event details**
7. Click **Send**

### Multiple Calendars

Repeat for each calendar you want Pepper to access:
- Work calendar
- Personal calendar
- Family calendar

Pepper will see these as read-only subscriptions in her account.

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
3. **IP Restriction**: Optionally restrict API keys to EC2 IP: `13.247.25.37`
4. **Rotation**: Periodically delete and recreate OAuth tokens (every 6-12 months)
5. **Monitoring**: Check Pepper's Gmail regularly for unexpected access

---

## Backup OAuth Credentials

See [backup-restore-guide.md](backup-restore-guide.md) for backing up:
- `~/.clawdbot/` (includes credentials)
- `~/.gog/` (OAuth tokens)
- `/tmp/pepper-credentials.json` (keep local copy too)

---

## Troubleshooting

### "Access blocked: This app's request is invalid"
- App is still in testing mode
- Make sure Pepper's email is added as a test user in Google Cloud Console

### "gog: command not found"
- Install globally: `npm install -g @go-on-git/gog`
- Check PATH: `echo $PATH | grep npm`

### "Authentication failed"
- Delete tokens: `rm -rf ~/.gog/`
- Re-authenticate: `gog auth add pepper@yourdomain.com`

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

# Configure in moltbot
GOG_ACCOUNTS=personal@gmail.com,work@company.com
```

Each requires separate OAuth authorization with read-only scopes:
- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/calendar.events.readonly`
