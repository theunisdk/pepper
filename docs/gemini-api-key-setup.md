# Gemini API Key Setup & Security

This guide covers creating a locked-down Gemini API key for use with OpenClaw.

## Create API Key

### Option 1: Google AI Studio (Simpler)
1. Go to https://aistudio.google.com/apikey
2. Click **Create API Key**
3. Select or create a Google Cloud project

### Option 2: Google Cloud Console (More Control)
1. Go to https://console.cloud.google.com/apis/credentials
2. Click **Create Credentials > API Key**
3. This gives more restriction options

## Security Restrictions

After creating the key, click on it to configure restrictions.

### 1. IP Address Restriction (Most Important)

Locks the key to only work from your EC2 instance.

- Select **IP addresses** under Application restrictions
- Add your EC2 Elastic IP: `YOUR_EC2_IP`
- The key becomes useless if leaked - only works from your server

### 2. API Restriction

Limits what Google APIs this key can access.

1. First, enable the Generative Language API:
   - Go to https://console.cloud.google.com/apis/library
   - Search for **"Generative Language API"**
   - Click **Enable**

2. Then restrict the key:
   - Select **Restrict key**
   - Choose only: **Generative Language API**

Note: The API may also appear as "Gemini API" or under Vertex AI.

### 3. Quotas (Rate Limiting)

Prevents runaway usage.

1. Go to **APIs & Services > Quotas**
2. Find "Generative Language API"
3. Set reasonable daily limits:
   - Requests per day: 1,000 (adjust based on usage)
   - Requests per minute: 60

### 4. Billing Alerts

Get notified before unexpected charges.

1. Go to **Billing > Budgets & Alerts**
2. Click **Create Budget**
3. Set budget amount (e.g., $10/month)
4. Configure alerts at:
   - 50% of budget
   - 90% of budget
   - 100% of budget

## Security Summary

| Protection | Setting | Purpose |
|------------|---------|---------|
| IP Restriction | EC2 IP only (`YOUR_EC2_IP`) | Key useless outside your server |
| API Restriction | Generative Language API only | Can't be used for other Google services |
| Quotas | Daily/minute limits | Prevents runaway usage |
| Billing Alerts | Budget cap with notifications | Early warning on spending |

## If API Restriction Unavailable

If you can't find "Generative Language API" in the restriction dropdown:

1. The API may need to be enabled first (see step 2.1 above)
2. It might be listed under a different name:
   - Gemini API
   - Vertex AI API
   - AI Platform API

3. **At minimum, use IP restriction** - this is the most important protection

## Best Practices

- Never commit API keys to version control
- Rotate keys periodically
- Monitor usage in Google Cloud Console
- Use separate keys for different environments (dev/prod)
- Store the key securely on the server (OpenClaw config handles this)

## Updating the Key in OpenClaw

If you need to update the API key later:

```bash
# SSH to your instance
ssh -i ~/.ssh/openclaw_key.pem ubuntu@YOUR_EC2_IP

# Switch to clawd user
sudo -u clawd -i

# Update the configuration
openclaw configure
```
