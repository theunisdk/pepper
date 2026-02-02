/**
 * Message Transformer
 *
 * Converts between Gupshup webhook payloads and OpenClaw message envelopes.
 */

import type {
  GupshupMessagePayload,
  GupshupInboundContent,
  GupshupInboundTextContent,
  GupshupInboundImageContent,
  GupshupInboundDocumentContent,
  GupshupInboundAudioContent,
  GupshupInboundVideoContent,
  GupshupInboundLocationContent,
  GupshupInboundContactContent,
  GupshupInboundStickerContent,
  GupshupOutboundMessage,
  MessageEnvelope,
  MessageContent,
  MessageContentType,
} from './types.js';

const CHANNEL_ID = 'gupshup';

/**
 * Transform a Gupshup inbound message to an OpenClaw envelope
 */
export function transformInbound(
  payload: GupshupMessagePayload,
  recipientPhone: string
): MessageEnvelope {
  const content = transformInboundContent(payload.type, payload.payload);

  return {
    id: payload.id,
    channel: CHANNEL_ID,
    direction: 'inbound',
    sender: {
      id: normalizePhone(payload.sender.phone),
      name: payload.sender.name,
    },
    recipient: {
      id: normalizePhone(recipientPhone),
    },
    content,
    timestamp: Date.now(),
    replyTo: payload.context?.id,
    metadata: {
      gupshupId: payload.id,
      contextGsId: payload.context?.gsId,
    },
  };
}

/**
 * Transform an OpenClaw envelope to a Gupshup outbound message
 */
export function transformOutbound(envelope: MessageEnvelope): GupshupOutboundMessage {
  const { content } = envelope;

  switch (content.type) {
    case 'text':
      return {
        type: 'text',
        text: content.text ?? '',
      };

    case 'image':
      return {
        type: 'image',
        originalUrl: content.mediaUrl ?? '',
        caption: content.caption,
      };

    case 'document':
      return {
        type: 'file',
        url: content.mediaUrl ?? '',
        filename: content.filename ?? 'document',
      };

    case 'audio':
      return {
        type: 'audio',
        url: content.mediaUrl ?? '',
      };

    case 'video':
      return {
        type: 'video',
        url: content.mediaUrl ?? '',
        caption: content.caption,
      };

    case 'location':
      if (!content.location) {
        throw new Error('Location content is required for location messages');
      }
      return {
        type: 'location',
        latitude: content.location.latitude,
        longitude: content.location.longitude,
        name: content.location.name,
        address: content.location.address,
      };

    case 'sticker':
      // Stickers sent as images
      return {
        type: 'image',
        originalUrl: content.mediaUrl ?? '',
      };

    case 'contact':
      // Contacts not directly supported for outbound, send as text
      return {
        type: 'text',
        text: content.contact
          ? `Contact: ${content.contact.name}${content.contact.phone ? ` (${content.contact.phone})` : ''}`
          : 'Contact shared',
      };

    default:
      // Fallback to text
      return {
        type: 'text',
        text: content.text ?? '[Unsupported message type]',
      };
  }
}

/**
 * Transform inbound content based on message type
 */
function transformInboundContent(
  type: string,
  payload: GupshupInboundContent
): MessageContent {
  switch (type) {
    case 'text': {
      const textPayload = payload as GupshupInboundTextContent;
      return {
        type: 'text',
        text: textPayload.text,
      };
    }

    case 'image': {
      const imagePayload = payload as GupshupInboundImageContent;
      return {
        type: 'image',
        mediaUrl: imagePayload.url,
        mimeType: imagePayload.contentType,
        caption: imagePayload.caption,
      };
    }

    case 'document': {
      const docPayload = payload as GupshupInboundDocumentContent;
      return {
        type: 'document',
        mediaUrl: docPayload.url,
        mimeType: docPayload.contentType,
        filename: docPayload.filename,
        caption: docPayload.caption,
      };
    }

    case 'audio': {
      const audioPayload = payload as GupshupInboundAudioContent;
      return {
        type: 'audio',
        mediaUrl: audioPayload.url,
        mimeType: audioPayload.contentType,
      };
    }

    case 'video': {
      const videoPayload = payload as GupshupInboundVideoContent;
      return {
        type: 'video',
        mediaUrl: videoPayload.url,
        mimeType: videoPayload.contentType,
        caption: videoPayload.caption,
      };
    }

    case 'location': {
      const locPayload = payload as GupshupInboundLocationContent;
      return {
        type: 'location',
        location: {
          latitude: locPayload.latitude,
          longitude: locPayload.longitude,
          name: locPayload.name,
          address: locPayload.address,
        },
      };
    }

    case 'contact': {
      const contactPayload = payload as GupshupInboundContactContent;
      return {
        type: 'contact',
        contact: {
          name: contactPayload.name.formattedName,
          phone: contactPayload.phones?.[0]?.phone,
        },
      };
    }

    case 'sticker': {
      const stickerPayload = payload as GupshupInboundStickerContent;
      return {
        type: 'sticker',
        mediaUrl: stickerPayload.url,
        mimeType: stickerPayload.contentType,
      };
    }

    default:
      // Unknown type, try to extract text or return placeholder
      return {
        type: 'text' as MessageContentType,
        text: `[Received ${type} message]`,
      };
  }
}

/**
 * Normalize phone number (remove + prefix, spaces, dashes)
 */
function normalizePhone(phone: string): string {
  return phone.replace(/[^\d]/g, '');
}

/**
 * Create a text-only envelope (utility for error messages, etc.)
 */
export function createTextEnvelope(
  senderId: string,
  recipientId: string,
  text: string,
  direction: 'inbound' | 'outbound' = 'inbound'
): MessageEnvelope {
  return {
    id: generateId(),
    channel: CHANNEL_ID,
    direction,
    sender: { id: normalizePhone(senderId) },
    recipient: { id: normalizePhone(recipientId) },
    content: {
      type: 'text',
      text,
    },
    timestamp: Date.now(),
  };
}

/**
 * Generate a simple unique ID
 */
function generateId(): string {
  return `gs_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}
