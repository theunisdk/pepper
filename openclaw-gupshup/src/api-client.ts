/**
 * Gupshup WhatsApp API Client
 *
 * Handles all outbound API calls to Gupshup's WhatsApp Business API.
 */

import { request } from 'undici';
import type {
  GupshupConfig,
  GupshupOutboundMessage,
  GupshupSendResponse,
  GupshupApiError,
  GupshupTextMessage,
  GupshupImageMessage,
  GupshupDocumentMessage,
  GupshupAudioMessage,
  GupshupVideoMessage,
  GupshupLocationMessage,
  GupshupTemplateMessage,
} from './types.js';

const GUPSHUP_API_BASE = 'https://api.gupshup.io/wa/api/v1';
const DEFAULT_TIMEOUT = 30000; // 30 seconds
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 1000;

export interface SendOptions {
  /** Retry on transient failures */
  retry?: boolean;
  /** Timeout in milliseconds */
  timeout?: number;
}

export class GupshupApiClient {
  private readonly apiKey: string;
  private readonly sourcePhone: string;
  private readonly businessName: string;

  constructor(config: GupshupConfig) {
    this.apiKey = config.apiKey;
    this.sourcePhone = config.sourcePhone;
    this.businessName = config.businessName ?? 'Assistant';
  }

  /**
   * Send a text message
   */
  async sendText(
    destination: string,
    text: string,
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupTextMessage = {
      type: 'text',
      text,
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Send an image message
   */
  async sendImage(
    destination: string,
    imageUrl: string,
    caption?: string,
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupImageMessage = {
      type: 'image',
      originalUrl: imageUrl,
      caption,
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Send a document/file message
   */
  async sendDocument(
    destination: string,
    documentUrl: string,
    filename: string,
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupDocumentMessage = {
      type: 'file',
      url: documentUrl,
      filename,
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Send an audio message
   */
  async sendAudio(
    destination: string,
    audioUrl: string,
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupAudioMessage = {
      type: 'audio',
      url: audioUrl,
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Send a video message
   */
  async sendVideo(
    destination: string,
    videoUrl: string,
    caption?: string,
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupVideoMessage = {
      type: 'video',
      url: videoUrl,
      caption,
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Send a location message
   */
  async sendLocation(
    destination: string,
    latitude: number,
    longitude: number,
    name?: string,
    address?: string,
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupLocationMessage = {
      type: 'location',
      latitude,
      longitude,
      name,
      address,
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Send a template message (for use outside 24-hour session window)
   */
  async sendTemplate(
    destination: string,
    templateId: string,
    params?: string[],
    options?: SendOptions
  ): Promise<GupshupSendResponse> {
    const message: GupshupTemplateMessage = {
      type: 'template',
      template: {
        id: templateId,
        params,
      },
    };
    return this.sendMessage(destination, message, options);
  }

  /**
   * Core send message method
   */
  async sendMessage(
    destination: string,
    message: GupshupOutboundMessage,
    options: SendOptions = {}
  ): Promise<GupshupSendResponse> {
    const { retry = true, timeout = DEFAULT_TIMEOUT } = options;

    // Build form data (Gupshup uses x-www-form-urlencoded)
    const formData = new URLSearchParams();
    formData.append('channel', 'whatsapp');
    formData.append('source', this.normalizePhone(this.sourcePhone));
    formData.append('destination', this.normalizePhone(destination));
    formData.append('message', JSON.stringify(message));
    formData.append('src.name', this.businessName);

    let lastError: Error | undefined;
    const maxAttempts = retry ? MAX_RETRIES : 1;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const response = await request(`${GUPSHUP_API_BASE}/msg`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'apikey': this.apiKey,
          },
          body: formData.toString(),
          bodyTimeout: timeout,
          headersTimeout: timeout,
        });

        const body = await response.body.json() as GupshupSendResponse;

        // Handle rate limiting
        if (response.statusCode === 429) {
          if (attempt < maxAttempts) {
            await this.delay(RETRY_DELAY_MS * attempt);
            continue;
          }
          throw this.createApiError('Rate limited', 'RATE_LIMITED', 429);
        }

        // Handle auth errors (don't retry)
        if (response.statusCode === 401 || response.statusCode === 403) {
          throw this.createApiError(
            'Authentication failed. Check your API key.',
            'AUTH_FAILED',
            response.statusCode
          );
        }

        // Handle session expired (outside 24hr window)
        if (response.statusCode === 470 || body.error?.code === '470') {
          throw this.createApiError(
            'Session expired. User must message first or use a template.',
            'SESSION_EXPIRED',
            470
          );
        }

        // Handle server errors (retry)
        if (response.statusCode >= 500) {
          if (attempt < maxAttempts) {
            await this.delay(RETRY_DELAY_MS * attempt);
            continue;
          }
          throw this.createApiError(
            `Server error: ${response.statusCode}`,
            'SERVER_ERROR',
            response.statusCode
          );
        }

        // Handle API-level errors
        if (body.status === 'error' && body.error) {
          throw this.createApiError(
            body.error.message,
            body.error.code,
            response.statusCode
          );
        }

        return body;
      } catch (error) {
        lastError = error as Error;

        // Don't retry on non-transient errors
        if (
          error instanceof Error &&
          'code' in error &&
          ['AUTH_FAILED', 'SESSION_EXPIRED'].includes((error as GupshupApiError).code)
        ) {
          throw error;
        }

        // Retry on network errors
        if (attempt < maxAttempts) {
          await this.delay(RETRY_DELAY_MS * attempt);
          continue;
        }
      }
    }

    throw lastError ?? new Error('Unknown error sending message');
  }

  /**
   * Normalize phone number to E.164 format without +
   */
  private normalizePhone(phone: string): string {
    // Remove all non-digit characters except leading +
    let normalized = phone.replace(/[^\d+]/g, '');
    // Remove leading +
    if (normalized.startsWith('+')) {
      normalized = normalized.slice(1);
    }
    return normalized;
  }

  /**
   * Create an API error with proper typing
   */
  private createApiError(
    message: string,
    code: string,
    statusCode?: number
  ): GupshupApiError {
    const error = new Error(message) as GupshupApiError;
    error.name = 'GupshupApiError';
    error.code = code;
    error.statusCode = statusCode;
    return error;
  }

  /**
   * Promise-based delay
   */
  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
