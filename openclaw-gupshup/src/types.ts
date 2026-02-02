/**
 * Gupshup WhatsApp Adapter Types
 */

// =============================================================================
// Configuration Types
// =============================================================================

export interface TemplateConfig {
  id: string;
  paramCount?: number;
}

/** DM policy for access control */
export type DmPolicy = 'open' | 'allowlist' | 'pairing';

/** Configuration for a single Gupshup account */
export interface GupshupAccountConfig {
  apiKey?: string;
  apiKeyFile?: string;
  appId: string;
  phoneNumber: string;
  businessName?: string;
  webhookSecret?: string;
  templates?: Record<string, TemplateConfig>;
}

/** Main configuration for the Gupshup channel */
export interface GupshupConfig {
  /** API key (use this OR apiKeyFile) */
  apiKey?: string;
  /** Path to file containing API key */
  apiKeyFile?: string;
  /** Gupshup App ID */
  appId: string;
  /** Source phone number (E.164 format) */
  sourcePhone: string;
  /** Business name shown to recipients */
  businessName?: string;
  /** Webhook signature secret */
  webhookSecret?: string;
  /** Webhook HTTP path */
  webhookPath?: string;
  /** Pre-approved message templates */
  templates?: Record<string, TemplateConfig>;

  // Access control
  /** DM policy: 'open' (anyone), 'allowlist' (specific numbers), 'pairing' (requires pairing) */
  dmPolicy?: DmPolicy;
  /** Allowed phone numbers when dmPolicy is 'allowlist' (E.164 format) */
  allowFrom?: string[];

  // Multi-account support
  /** Named accounts for multi-account setups */
  accounts?: Record<string, GupshupAccountConfig>;
  /** Default account name to use (if accounts defined) */
  defaultAccount?: string;
}

/** Resolved account with all required fields */
export interface ResolvedAccount {
  name: string;
  apiKey: string;
  appId: string;
  phoneNumber: string;
  businessName: string;
  webhookSecret?: string;
  templates?: Record<string, TemplateConfig>;
}

// =============================================================================
// Gupshup API Types (Outbound)
// =============================================================================

export interface GupshupTextMessage {
  type: 'text';
  text: string;
}

export interface GupshupImageMessage {
  type: 'image';
  originalUrl: string;
  previewUrl?: string;
  caption?: string;
}

export interface GupshupDocumentMessage {
  type: 'file';
  url: string;
  filename: string;
}

export interface GupshupAudioMessage {
  type: 'audio';
  url: string;
}

export interface GupshupVideoMessage {
  type: 'video';
  url: string;
  caption?: string;
}

export interface GupshupLocationMessage {
  type: 'location';
  longitude: number;
  latitude: number;
  name?: string;
  address?: string;
}

export interface GupshupTemplateMessage {
  type: 'template';
  template: {
    id: string;
    params?: string[];
  };
}

export type GupshupOutboundMessage =
  | GupshupTextMessage
  | GupshupImageMessage
  | GupshupDocumentMessage
  | GupshupAudioMessage
  | GupshupVideoMessage
  | GupshupLocationMessage
  | GupshupTemplateMessage;

export interface GupshupSendRequest {
  channel: 'whatsapp';
  source: string;
  destination: string;
  message: GupshupOutboundMessage;
  'src.name'?: string;
}

export interface GupshupSendResponse {
  status: 'submitted' | 'error';
  messageId?: string;
  error?: {
    code: string;
    message: string;
  };
}

// =============================================================================
// Gupshup Webhook Types (Inbound)
// =============================================================================

export interface GupshupWebhookPayload {
  app: string;
  timestamp: number;
  version: number;
  type: 'message' | 'message-event' | 'user-event';
  payload: GupshupMessagePayload | GupshupMessageEventPayload | GupshupUserEventPayload;
}

export interface GupshupMessagePayload {
  id: string;
  source: string;
  type: 'text' | 'image' | 'document' | 'audio' | 'video' | 'location' | 'contact' | 'sticker';
  payload: GupshupInboundContent;
  sender: {
    phone: string;
    name?: string;
    country_code?: string;
    dial_code?: string;
  };
  context?: {
    id: string;
    gsId: string;
  };
}

export interface GupshupInboundTextContent {
  text: string;
}

export interface GupshupInboundImageContent {
  url: string;
  contentType: string;
  caption?: string;
}

export interface GupshupInboundDocumentContent {
  url: string;
  contentType: string;
  filename?: string;
  caption?: string;
}

export interface GupshupInboundAudioContent {
  url: string;
  contentType: string;
}

export interface GupshupInboundVideoContent {
  url: string;
  contentType: string;
  caption?: string;
}

export interface GupshupInboundLocationContent {
  longitude: number;
  latitude: number;
  name?: string;
  address?: string;
}

export interface GupshupInboundContactContent {
  name: {
    firstName: string;
    lastName?: string;
    formattedName: string;
  };
  phones?: Array<{
    phone: string;
    type?: string;
  }>;
}

export interface GupshupInboundStickerContent {
  url: string;
  contentType: string;
}

export type GupshupInboundContent =
  | GupshupInboundTextContent
  | GupshupInboundImageContent
  | GupshupInboundDocumentContent
  | GupshupInboundAudioContent
  | GupshupInboundVideoContent
  | GupshupInboundLocationContent
  | GupshupInboundContactContent
  | GupshupInboundStickerContent;

export interface GupshupMessageEventPayload {
  id: string;
  gsId?: string;
  type: 'sent' | 'delivered' | 'read' | 'failed' | 'enqueued';
  destination: string;
  payload?: {
    code?: string;
    reason?: string;
  };
}

export interface GupshupUserEventPayload {
  phone: string;
  type: 'opted-in' | 'opted-out' | 'sandbox-start';
}

// =============================================================================
// OpenClaw Message Envelope Types
// =============================================================================

export type MessageContentType = 'text' | 'image' | 'document' | 'audio' | 'video' | 'location' | 'contact' | 'sticker';

export interface MessageContent {
  type: MessageContentType;
  text?: string;
  mediaUrl?: string;
  mimeType?: string;
  filename?: string;
  caption?: string;
  location?: {
    latitude: number;
    longitude: number;
    name?: string;
    address?: string;
  };
  contact?: {
    name: string;
    phone?: string;
  };
}

export interface MessageEnvelope {
  id: string;
  channel: string;
  direction: 'inbound' | 'outbound';
  sender: {
    id: string;
    name?: string;
  };
  recipient: {
    id: string;
    name?: string;
  };
  content: MessageContent;
  timestamp: number;
  replyTo?: string;
  metadata?: Record<string, unknown>;
}

// =============================================================================
// Channel Adapter Types (OpenClaw Plugin Interface)
// =============================================================================

export interface SendResult {
  success: boolean;
  messageId?: string;
  error?: string;
}

export interface ChannelStatus {
  connected: boolean;
  error?: string;
  lastActivity?: number;
}

export interface ChannelAdapter {
  id: string;
  name: string;

  initialize(config: GupshupConfig): Promise<void>;
  start(): Promise<void>;
  stop(): Promise<void>;

  sendMessage(envelope: MessageEnvelope): Promise<SendResult>;

  isConnected(): boolean;
  getStatus(): ChannelStatus;
}

// =============================================================================
// Session Tracking Types
// =============================================================================

export interface SessionInfo {
  phone: string;
  lastMessageAt: number;
  isActive: boolean;
}

// =============================================================================
// Error Types
// =============================================================================

export class GupshupApiError extends Error {
  constructor(
    message: string,
    public code: string,
    public statusCode?: number
  ) {
    super(message);
    this.name = 'GupshupApiError';
  }
}

export class SessionExpiredError extends Error {
  constructor(public phone: string) {
    super(`Session expired for ${phone}. Use a template message.`);
    this.name = 'SessionExpiredError';
  }
}

export class WebhookValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WebhookValidationError';
  }
}

export class AccessDeniedError extends Error {
  constructor(public phone: string, public policy: DmPolicy) {
    super(`Access denied for ${phone}. DM policy: ${policy}`);
    this.name = 'AccessDeniedError';
  }
}

// =============================================================================
// Health Check Types
// =============================================================================

export interface HealthStatus {
  healthy: boolean;
  channel: string;
  accounts: AccountHealthStatus[];
  timestamp: number;
}

export interface AccountHealthStatus {
  name: string;
  phoneNumber: string;
  connected: boolean;
  lastActivity?: number;
  error?: string;
}
