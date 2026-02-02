# OpenClaw Gupshup WhatsApp Adapter

A WhatsApp Business API adapter for [OpenClaw](https://openclaw.ai/) using [Gupshup](https://www.gupshup.io/) as the official Meta partner.

## Why Gupshup?

| Feature | Baileys (Default) | Gupshup (This Adapter) |
|---------|-------------------|------------------------|
| **Stability** | Gets blocked frequently | Official Meta Partner |
| **Protocol** | Reverse-engineered | Official REST API |
| **Business Use** | ToS violation risk | Officially supported |
| **Auth** | QR code scanning | API key |
| **Cost** | Free | Per-message pricing |

## Installation

### Option 1: OpenClaw Plugin Install

```bash
openclaw plugins install @anthropic/openclaw-gupshup
```

### Option 2: Manual Installation

1. Clone/copy to your extensions directory:
   ```bash
   cp -r openclaw-gupshup ~/.openclaw/extensions/gupshup
   ```

2. Build the plugin:
   ```bash
   cd ~/.openclaw/extensions/gupshup
   npm install
   npm run build
   ```

3. Add to your OpenClaw config (`~/.openclaw/openclaw.json`):
   ```json
   {
     "plugins": {
       "load": {
         "paths": ["~/.openclaw/extensions/gupshup"]
       }
     }
   }
   ```

## Configuration

### Basic Configuration (Single Account)

```json
{
  "channels": {
    "gupshup": {
      "enabled": true,
      "apiKey": "your-gupshup-api-key",
      "appId": "your-gupshup-app-id",
      "sourcePhone": "+1234567890",
      "businessName": "My Assistant"
    }
  }
}
```

### Using API Key from File

For security, you can store the API key in a file:

```json
{
  "channels": {
    "gupshup": {
      "enabled": true,
      "apiKeyFile": "~/.secrets/gupshup-api-key",
      "appId": "your-gupshup-app-id",
      "sourcePhone": "+1234567890"
    }
  }
}
```

### Access Control (DM Policy)

Control who can message your bot:

```json
{
  "channels": {
    "gupshup": {
      "enabled": true,
      "apiKey": "...",
      "appId": "...",
      "sourcePhone": "+1234567890",
      "dmPolicy": "allowlist",
      "allowFrom": [
        "+15551234567",
        "+15559876543"
      ]
    }
  }
}
```

**DM Policy Options:**
- `open` (default) - Anyone can message
- `allowlist` - Only numbers in `allowFrom` array can message
- `pairing` - Requires explicit approval (integrates with OpenClaw pairing)

### Multi-Account Configuration

Run multiple WhatsApp numbers:

```json
{
  "channels": {
    "gupshup": {
      "enabled": true,
      "apiKey": "shared-api-key",
      "dmPolicy": "allowlist",
      "accounts": {
        "sales": {
          "appId": "sales-app-id",
          "phoneNumber": "+14155551234",
          "businessName": "Sales Team"
        },
        "support": {
          "appId": "support-app-id",
          "phoneNumber": "+14155559999",
          "businessName": "Support Team",
          "apiKey": "different-api-key"
        }
      },
      "defaultAccount": "sales"
    }
  }
}
```

### Full Configuration Reference

| Option | Required | Description |
|--------|----------|-------------|
| `apiKey` | Yes* | Gupshup API key |
| `apiKeyFile` | Yes* | Path to file containing API key |
| `appId` | Yes | Gupshup WhatsApp App ID |
| `sourcePhone` | Yes | Your WhatsApp Business phone number (E.164) |
| `businessName` | No | Business name shown to recipients (default: "Assistant") |
| `webhookSecret` | No | Secret for webhook signature validation |
| `webhookPath` | No | HTTP path for webhooks (default: `/webhooks/gupshup`) |
| `dmPolicy` | No | Access control: `open`, `allowlist`, or `pairing` |
| `allowFrom` | No | Array of allowed phone numbers (E.164 format) |
| `templates` | No | Pre-approved message templates |
| `accounts` | No | Named accounts for multi-account setups |
| `defaultAccount` | No | Default account name |

\* Either `apiKey` or `apiKeyFile` is required

## Health Check

The plugin exposes a health check endpoint at `{webhookPath}/health`:

```bash
curl http://localhost:18789/webhooks/gupshup/health
```

Response:
```json
{
  "healthy": true,
  "channel": "gupshup",
  "accounts": [
    {
      "name": "default",
      "phoneNumber": "+1234567890",
      "connected": true,
      "lastActivity": 1704067200000
    }
  ],
  "timestamp": 1704067200000
}
```

## Template Messages

WhatsApp Business API requires pre-approved templates for messages sent outside the 24-hour session window.

### Session Rules
- **Active session**: User messaged within last 24 hours → free-form messages allowed
- **Expired session**: No user message in 24 hours → only template messages allowed

### Configuring Templates

1. Create templates in Gupshup dashboard
2. Wait for WhatsApp approval (usually 24-48 hours)
3. Add to config:

```json
{
  "templates": {
    "followup": {
      "id": "gupshup_template_12345",
      "paramCount": 2
    }
  }
}
```

## Gupshup Account Setup

1. Create account at [gupshup.io](https://www.gupshup.io)
2. Complete Meta Business verification
3. Create WhatsApp Business app in Gupshup dashboard
4. Note your **API Key** and **App ID**
5. Register and verify your business phone number
6. Configure webhook URL: `https://your-server/webhooks/gupshup`
7. (Optional) Create and get approval for message templates

## Development

### Build

```bash
npm install
npm run build
```

### Watch Mode

```bash
npm run dev
```

### Run Tests

```bash
npm test
```

## Architecture

```
src/
├── index.ts              # Plugin entry point
├── types.ts              # TypeScript interfaces
├── accounts.ts           # Multi-account resolution
├── api-client.ts         # Gupshup REST API client
├── webhook-handler.ts    # Inbound message handler
├── message-transformer.ts # Format conversion
├── probe.ts              # Health check
└── gupshup-channel.ts    # Channel adapter
```

### Message Flow

**Inbound (WhatsApp → OpenClaw)**:
```
WhatsApp → Gupshup → Webhook → Access Check → WebhookHandler → MessageTransformer → OpenClaw
```

**Outbound (OpenClaw → WhatsApp)**:
```
OpenClaw → GupshupChannel → Account Resolution → MessageTransformer → GupshupApiClient → Gupshup → WhatsApp
```

## Standalone Usage

The adapter can be used outside OpenClaw:

```typescript
import { GupshupChannel, createGupshupChannel } from '@anthropic/openclaw-gupshup';

const channel = createGupshupChannel({
  apiKey: 'your-api-key',
  appId: 'your-app-id',
  sourcePhone: '+1234567890',
  dmPolicy: 'allowlist',
  allowFrom: ['+15551234567'],
});

await channel.initialize(config);
await channel.start();

// Check if sender has access
if (channel.checkAccess('+15551234567')) {
  const result = await channel.sendMessage({
    id: 'msg-1',
    channel: 'gupshup',
    direction: 'outbound',
    sender: { id: '+1234567890' },
    recipient: { id: '+15551234567' },
    content: { type: 'text', text: 'Hello!' },
    timestamp: Date.now(),
  });
}

// Get health status
const health = await channel.checkHealth();
console.log(health.healthy);
```

## Troubleshooting

### "Session expired" errors
- User hasn't messaged in 24+ hours
- Configure a template message for follow-ups
- Or wait for user to initiate contact

### "Authentication failed" errors
- Check your API key is correct
- If using `apiKeyFile`, verify the file exists and is readable
- Ensure API key has WhatsApp permissions

### "Access denied" errors
- Check `dmPolicy` setting
- If using `allowlist`, ensure the sender's number is in `allowFrom`
- Numbers must be in E.164 format (+1234567890)

### Webhook not receiving messages
- Verify webhook URL is publicly accessible
- Check firewall allows Gupshup IPs
- Verify webhook is registered in Gupshup dashboard
- Check health endpoint: `GET /webhooks/gupshup/health`

### Multi-account issues
- Ensure each account has a unique `appId` and `phoneNumber`
- Check that `defaultAccount` matches an account name
- Account-level settings override top-level settings

## License

MIT

## Links

- [OpenClaw](https://openclaw.ai/)
- [OpenClaw Plugins Documentation](https://docs.openclaw.ai/plugin)
- [Gupshup WhatsApp API](https://docs.gupshup.io/docs/whatsapp-business)
- [Gupshup Dashboard](https://www.gupshup.io/developer/dashboard)
