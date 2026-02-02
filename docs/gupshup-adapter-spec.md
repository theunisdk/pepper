# Gupshup WhatsApp Adapter for OpenClaw

## Overview

This document specifies the implementation of a Gupshup WhatsApp Business API adapter for OpenClaw (formerly Moltbot/Clawdbot). This replaces the Baileys-based WhatsApp integration which frequently gets blocked due to its unofficial nature.

## Why Gupshup?

| Aspect | Baileys (Current) | Gupshup (This Adapter) |
|--------|-------------------|------------------------|
| **Type** | Unofficial reverse-engineering | Official Meta Partner API |
| **Stability** | Gets blocked frequently | Stable (Meta Partner 2023/2024) |
| **Auth** | QR code scan | API Key + Webhook |
| **Protocol** | WebSocket simulation | REST API + Webhooks |
| **Business Use** | Risky, ToS violation | Officially supported |
| **Cost** | Free | Per-message pricing |

## Architecture

### Plugin-Based (No Fork Required)

OpenClaw supports external channel adapters via its plugin system:
- Plugins loaded from `~/.openclaw/extensions/` or config paths
- Install via `openclaw plugins install <package>`
- Independent versioning from OpenClaw core

### Package Structure

```
openclaw-gupshup/
├── package.json              # npm package with openclaw.extensions
├── openclaw.plugin.json      # Plugin manifest with config schema
├── tsconfig.json             # TypeScript configuration
├── src/
│   ├── index.ts              # Plugin entry point, registers channel
│   ├── gupshup-channel.ts    # Channel adapter (OpenClaw interface)
│   ├── api-client.ts         # Gupshup REST API client
│   ├── webhook-handler.ts    # Inbound message HTTP handler
│   ├── message-transformer.ts # Format conversion utilities
│   └── types.ts              # TypeScript interfaces
├── test/
│   ├── api-client.test.ts
│   ├── webhook-handler.test.ts
│   └── message-transformer.test.ts
└── README.md
```

## Gupshup API Integration

### Authentication
- **API Key**: Required for all outbound API calls
- **App ID**: Identifies your Gupshup WhatsApp app
- **Webhook Secret**: Optional, for validating inbound webhooks

### Outbound Messages (Send)

**Endpoint**: `POST https://api.gupshup.io/wa/api/v1/msg`

**Headers**:
```
Content-Type: application/x-www-form-urlencoded
apikey: <your-api-key>
```

**Message Types**:

1. **Text Message**
```
channel=whatsapp
source=<your-phone>
destination=<recipient-phone>
message={"type":"text","text":"Hello"}
src.name=<business-name>
```

2. **Image Message**
```
message={"type":"image","originalUrl":"https://...","caption":"optional"}
```

3. **Document Message**
```
message={"type":"file","url":"https://...","filename":"doc.pdf"}
```

4. **Template Message** (for messages outside 24hr window)
```
message={"type":"template","template":{"id":"<template-id>","params":["param1","param2"]}}
```

### Inbound Messages (Receive via Webhook)

**Webhook Payload Format**:
```json
{
  "app": "YourApp",
  "timestamp": 1234567890,
  "version": 2,
  "type": "message",
  "payload": {
    "id": "message-id",
    "source": "sender-phone",
    "type": "text|image|document|audio|video|location|contact",
    "payload": {
      "text": "message content"
    },
    "sender": {
      "phone": "sender-phone",
      "name": "Sender Name"
    }
  }
}
```

**Message Types to Handle**:
- `text` - Plain text messages
- `image` - Photos with optional caption
- `document` - PDF, DOC, etc.
- `audio` - Voice messages
- `video` - Video files
- `location` - GPS coordinates
- `contact` - Contact cards

### Delivery Status Webhooks
```json
{
  "type": "message-event",
  "payload": {
    "id": "message-id",
    "type": "sent|delivered|read|failed",
    "destination": "recipient-phone"
  }
}
```

## OpenClaw Integration

### Plugin Manifest (`openclaw.plugin.json`)

```json
{
  "id": "gupshup",
  "name": "Gupshup WhatsApp",
  "version": "1.0.0",
  "description": "WhatsApp Business API via Gupshup - official Meta partner",
  "author": "Your Name",
  "openclaw": {
    "minVersion": "0.50.0",
    "channel": true
  },
  "configSchema": {
    "type": "object",
    "properties": {
      "apiKey": {
        "type": "string",
        "description": "Gupshup API key",
        "sensitive": true
      },
      "appId": {
        "type": "string",
        "description": "Gupshup WhatsApp App ID"
      },
      "sourcePhone": {
        "type": "string",
        "description": "Your WhatsApp Business phone number (with country code)"
      },
      "businessName": {
        "type": "string",
        "description": "Business name shown to recipients"
      },
      "webhookSecret": {
        "type": "string",
        "description": "Optional secret for webhook validation",
        "sensitive": true
      },
      "templates": {
        "type": "object",
        "description": "Pre-approved template mappings",
        "additionalProperties": {
          "type": "object",
          "properties": {
            "id": { "type": "string" },
            "paramCount": { "type": "number" }
          }
        }
      }
    },
    "required": ["apiKey", "appId", "sourcePhone"]
  }
}
```

### User Configuration

Users configure in `~/.openclaw/openclaw.json`:

```json
{
  "channels": {
    "gupshup": {
      "enabled": true,
      "apiKey": "your-gupshup-api-key",
      "appId": "your-app-id",
      "sourcePhone": "+1234567890",
      "businessName": "My Assistant",
      "templates": {
        "notification": {
          "id": "template_abc123",
          "paramCount": 1
        }
      }
    }
  }
}
```

### Channel Interface Implementation

The adapter must implement OpenClaw's channel interface:

```typescript
interface ChannelAdapter {
  id: string;
  name: string;

  // Lifecycle
  initialize(config: ChannelConfig): Promise<void>;
  start(): Promise<void>;
  stop(): Promise<void>;

  // Messaging
  sendMessage(envelope: MessageEnvelope): Promise<SendResult>;

  // Status
  isConnected(): boolean;
  getStatus(): ChannelStatus;
}
```

### Message Envelope Format

OpenClaw uses a unified envelope format:

```typescript
interface MessageEnvelope {
  id: string;
  channel: string;           // "gupshup"
  direction: "inbound" | "outbound";
  sender: {
    id: string;              // phone number
    name?: string;
  };
  recipient: {
    id: string;              // phone number
  };
  content: {
    type: "text" | "image" | "document" | "audio" | "video" | "location";
    text?: string;
    mediaUrl?: string;
    mimeType?: string;
    filename?: string;
    caption?: string;
    location?: { lat: number; lng: number };
  };
  timestamp: number;
  metadata?: Record<string, unknown>;
}
```

## Template Message Handling

WhatsApp Business API requires pre-approved templates for messages sent outside the 24-hour session window.

### Session Window Rules
- **Session active**: User messaged within last 24 hours → free-form messages allowed
- **Session expired**: No user message in 24 hours → only template messages allowed

### Implementation Approach
1. Track last message timestamp per conversation
2. Before sending, check if session is active
3. If session expired:
   - If template configured for message type → use template
   - If no template → return error, do not auto-fallback
4. Log template usage for billing awareness

### Template Configuration
Users pre-configure approved templates:
```json
{
  "templates": {
    "followup": {
      "id": "gupshup_template_id",
      "paramCount": 2
    }
  }
}
```

## Error Handling

### API Errors
| Code | Meaning | Action |
|------|---------|--------|
| 401 | Invalid API key | Log error, mark channel unhealthy |
| 429 | Rate limited | Exponential backoff retry |
| 470 | Session expired | Require template message |
| 500 | Gupshup server error | Retry with backoff |

### Webhook Validation
- Optionally validate webhook signature using `webhookSecret`
- Reject malformed payloads with 400
- Return 200 quickly, process async

## Security Considerations

1. **API Key Storage**: Marked as `sensitive` in config schema, not logged
2. **Webhook Endpoint**: Should only be accessible from Gupshup IPs (optional IP allowlist)
3. **Phone Number Privacy**: Don't log full phone numbers in production
4. **Message Content**: Follow OpenClaw's existing message handling security

## Testing Plan

### Unit Tests
- API client: Mock HTTP responses, verify request formatting
- Webhook handler: Parse various payload types
- Message transformer: Verify bidirectional conversion

### Integration Tests
1. Configure adapter with test Gupshup account
2. Send message from WhatsApp to Gupshup number
3. Verify message received in OpenClaw
4. Reply from OpenClaw
5. Verify reply delivered to WhatsApp
6. Test template message (outside session window)

### Manual Testing Checklist
- [ ] Text message send/receive
- [ ] Image send/receive
- [ ] Document send/receive
- [ ] Voice message receive
- [ ] Location receive
- [ ] Template message send
- [ ] Session expiry handling
- [ ] Error recovery (network issues)
- [ ] Gateway restart preserves state

## Gupshup Account Setup (Prerequisites)

1. Create account at [gupshup.io](https://www.gupshup.io)
2. Complete Meta Business verification
3. Create WhatsApp Business app in Gupshup dashboard
4. Note your API Key and App ID
5. Register your business phone number
6. Configure webhook URL: `https://your-server/webhooks/gupshup`
7. Create and get approval for message templates
8. Test with Gupshup's sandbox before going live

## References

- [Gupshup WhatsApp API Docs](https://docs.gupshup.io/docs/whatsapp-business)
- [Gupshup Send Message API](https://docs.gupshup.io/docs/send-message-api)
- [OpenClaw Plugin Docs](https://docs.openclaw.ai/plugin)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw Extensions Examples](https://github.com/openclaw/openclaw/tree/main/extensions)
