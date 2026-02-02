/**
 * Webhook Handler
 *
 * Handles incoming webhook requests from Gupshup for inbound messages
 * and delivery status updates.
 */

import { createHmac, timingSafeEqual } from 'crypto';
import type {
  GupshupWebhookPayload,
  GupshupMessagePayload,
  GupshupMessageEventPayload,
  GupshupUserEventPayload,
  GupshupConfig,
  MessageEnvelope,
  WebhookValidationError,
} from './types.js';
import { transformInbound } from './message-transformer.js';

export interface WebhookHandlerOptions {
  /** Called when a new message is received */
  onMessage?: (envelope: MessageEnvelope) => void | Promise<void>;
  /** Called when a delivery status update is received */
  onStatusUpdate?: (event: DeliveryStatusEvent) => void | Promise<void>;
  /** Called when a user opts in/out */
  onUserEvent?: (event: UserEvent) => void | Promise<void>;
}

export interface DeliveryStatusEvent {
  messageId: string;
  gupshupId?: string;
  destination: string;
  status: 'sent' | 'delivered' | 'read' | 'failed' | 'enqueued';
  errorCode?: string;
  errorReason?: string;
  timestamp: number;
}

export interface UserEvent {
  phone: string;
  type: 'opted-in' | 'opted-out' | 'sandbox-start';
  timestamp: number;
}

export class WebhookHandler {
  private readonly config: GupshupConfig;
  private readonly options: WebhookHandlerOptions;

  constructor(config: GupshupConfig, options: WebhookHandlerOptions = {}) {
    this.config = config;
    this.options = options;
  }

  /**
   * Handle an incoming webhook request
   *
   * @param body - Raw request body (string or object)
   * @param signature - Optional signature header for validation
   * @returns Response to send back to Gupshup (always 200 for valid requests)
   */
  async handleWebhook(
    body: string | GupshupWebhookPayload,
    signature?: string
  ): Promise<{ status: number; body: string }> {
    try {
      // Parse body if string
      const payload: GupshupWebhookPayload =
        typeof body === 'string' ? JSON.parse(body) : body;

      // Validate signature if secret is configured
      if (this.config.webhookSecret && signature) {
        const isValid = this.validateSignature(
          typeof body === 'string' ? body : JSON.stringify(body),
          signature
        );
        if (!isValid) {
          return {
            status: 401,
            body: JSON.stringify({ error: 'Invalid signature' }),
          };
        }
      }

      // Route based on payload type
      await this.routePayload(payload);

      // Always return 200 quickly to acknowledge receipt
      return {
        status: 200,
        body: JSON.stringify({ status: 'received' }),
      };
    } catch (error) {
      // Log error but still return 200 to prevent Gupshup retries
      // (unless it's a validation error)
      if (error instanceof Error && error.name === 'SyntaxError') {
        return {
          status: 400,
          body: JSON.stringify({ error: 'Invalid JSON' }),
        };
      }

      console.error('[Gupshup Webhook] Error processing webhook:', error);
      return {
        status: 200,
        body: JSON.stringify({ status: 'received', warning: 'Processing error' }),
      };
    }
  }

  /**
   * Route payload to appropriate handler based on type
   */
  private async routePayload(payload: GupshupWebhookPayload): Promise<void> {
    switch (payload.type) {
      case 'message':
        await this.handleMessage(payload.payload as GupshupMessagePayload);
        break;

      case 'message-event':
        await this.handleMessageEvent(payload.payload as GupshupMessageEventPayload);
        break;

      case 'user-event':
        await this.handleUserEvent(payload.payload as GupshupUserEventPayload);
        break;

      default:
        console.warn(`[Gupshup Webhook] Unknown payload type: ${payload.type}`);
    }
  }

  /**
   * Handle incoming message
   */
  private async handleMessage(payload: GupshupMessagePayload): Promise<void> {
    if (!this.options.onMessage) {
      return;
    }

    // Transform to OpenClaw envelope
    const envelope = transformInbound(payload, this.config.sourcePhone);

    // Call handler
    await this.options.onMessage(envelope);
  }

  /**
   * Handle delivery status update
   */
  private async handleMessageEvent(payload: GupshupMessageEventPayload): Promise<void> {
    if (!this.options.onStatusUpdate) {
      return;
    }

    const event: DeliveryStatusEvent = {
      messageId: payload.id,
      gupshupId: payload.gsId,
      destination: payload.destination,
      status: payload.type,
      errorCode: payload.payload?.code,
      errorReason: payload.payload?.reason,
      timestamp: Date.now(),
    };

    await this.options.onStatusUpdate(event);
  }

  /**
   * Handle user opt-in/out events
   */
  private async handleUserEvent(payload: GupshupUserEventPayload): Promise<void> {
    if (!this.options.onUserEvent) {
      return;
    }

    const event: UserEvent = {
      phone: payload.phone,
      type: payload.type,
      timestamp: Date.now(),
    };

    await this.options.onUserEvent(event);
  }

  /**
   * Validate webhook signature
   *
   * Gupshup uses HMAC-SHA256 for webhook signatures
   */
  private validateSignature(body: string, signature: string): boolean {
    if (!this.config.webhookSecret) {
      return true; // No secret configured, skip validation
    }

    try {
      const expectedSignature = createHmac('sha256', this.config.webhookSecret)
        .update(body)
        .digest('hex');

      // Use timing-safe comparison to prevent timing attacks
      const sigBuffer = Buffer.from(signature);
      const expectedBuffer = Buffer.from(expectedSignature);

      if (sigBuffer.length !== expectedBuffer.length) {
        return false;
      }

      return timingSafeEqual(sigBuffer, expectedBuffer);
    } catch {
      return false;
    }
  }
}

/**
 * Create a simple HTTP request handler function
 * This can be integrated with Express, Fastify, or raw Node.js http
 */
export function createWebhookMiddleware(
  config: GupshupConfig,
  options: WebhookHandlerOptions
): (body: string, signature?: string) => Promise<{ status: number; body: string }> {
  const handler = new WebhookHandler(config, options);
  return (body, signature) => handler.handleWebhook(body, signature);
}
