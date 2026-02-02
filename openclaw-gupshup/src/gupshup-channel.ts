/**
 * Gupshup Channel Adapter
 *
 * Implements the OpenClaw channel interface for Gupshup WhatsApp Business API.
 * Supports multi-account, access control policies, and health probes.
 */

import type {
  GupshupConfig,
  ChannelAdapter,
  ChannelStatus,
  MessageEnvelope,
  SendResult,
  SessionInfo,
  ResolvedAccount,
  DmPolicy,
  HealthStatus,
} from './types.js';
import { AccessDeniedError } from './types.js';
import { GupshupApiClient } from './api-client.js';
import { WebhookHandler, type DeliveryStatusEvent, type UserEvent } from './webhook-handler.js';
import { transformOutbound } from './message-transformer.js';
import { resolveAccounts, resolveDefaultAccount, findAccountByPhone } from './accounts.js';
import { GupshupProbe } from './probe.js';

const CHANNEL_ID = 'gupshup';
const CHANNEL_NAME = 'Gupshup WhatsApp';
const SESSION_WINDOW_MS = 24 * 60 * 60 * 1000; // 24 hours

export interface GupshupChannelEvents {
  /** Emitted when a message is received from WhatsApp */
  onMessage?: (envelope: MessageEnvelope) => void | Promise<void>;
  /** Emitted when a delivery status update is received */
  onStatusUpdate?: (event: DeliveryStatusEvent) => void | Promise<void>;
  /** Emitted when a user opts in/out */
  onUserEvent?: (event: UserEvent) => void | Promise<void>;
  /** Emitted when access is denied */
  onAccessDenied?: (phone: string, policy: DmPolicy) => void | Promise<void>;
}

export class GupshupChannel implements ChannelAdapter {
  readonly id = CHANNEL_ID;
  readonly name = CHANNEL_NAME;

  private config: GupshupConfig | null = null;
  private accounts: ResolvedAccount[] = [];
  private apiClients: Map<string, GupshupApiClient> = new Map();
  private webhookHandler: WebhookHandler | null = null;
  private probe: GupshupProbe | null = null;
  private connected = false;
  private lastActivity: number = 0;
  private lastError: string | undefined;
  private events: GupshupChannelEvents;

  // Session tracking: phone -> last message timestamp
  private sessions = new Map<string, SessionInfo>();

  // Access control: normalized phone numbers in allowlist
  private allowlist: Set<string> = new Set();

  constructor(events: GupshupChannelEvents = {}) {
    this.events = events;
  }

  /**
   * Initialize the channel with configuration
   */
  async initialize(config: GupshupConfig): Promise<void> {
    this.config = config;

    // Resolve accounts (handles multi-account and apiKeyFile)
    this.accounts = resolveAccounts(config);

    // Create API client for each account
    for (const account of this.accounts) {
      const client = new GupshupApiClient({
        apiKey: account.apiKey,
        appId: account.appId,
        sourcePhone: account.phoneNumber,
        businessName: account.businessName,
      });
      this.apiClients.set(account.name, client);
    }

    // Initialize access control allowlist
    if (config.allowFrom) {
      for (const phone of config.allowFrom) {
        this.allowlist.add(this.normalizePhone(phone));
      }
    }

    // Create health probe
    this.probe = new GupshupProbe(config);

    // Create webhook handler (uses default account for now)
    const defaultAccount = resolveDefaultAccount(config);
    this.webhookHandler = new WebhookHandler(
      {
        ...config,
        apiKey: defaultAccount.apiKey,
        sourcePhone: defaultAccount.phoneNumber,
        webhookSecret: defaultAccount.webhookSecret,
      },
      {
        onMessage: async (envelope) => {
          // Check access control
          if (!this.checkAccess(envelope.sender.id)) {
            if (this.events.onAccessDenied) {
              await this.events.onAccessDenied(
                envelope.sender.id,
                this.config?.dmPolicy ?? 'open'
              );
            }
            return; // Don't forward message
          }

          // Update session tracking
          this.updateSession(envelope.sender.id);
          this.lastActivity = Date.now();
          this.probe?.updateActivity(defaultAccount.name);

          // Forward to event handler
          if (this.events.onMessage) {
            await this.events.onMessage(envelope);
          }
        },
        onStatusUpdate: async (event) => {
          this.lastActivity = Date.now();
          this.probe?.updateActivity(defaultAccount.name);
          if (this.events.onStatusUpdate) {
            await this.events.onStatusUpdate(event);
          }
        },
        onUserEvent: async (event) => {
          if (this.events.onUserEvent) {
            await this.events.onUserEvent(event);
          }
        },
      }
    );
  }

  /**
   * Start the channel (mark as connected)
   */
  async start(): Promise<void> {
    if (!this.config || this.apiClients.size === 0) {
      throw new Error('Channel not initialized. Call initialize() first.');
    }

    this.connected = true;
    this.lastActivity = Date.now();
    this.lastError = undefined;
  }

  /**
   * Stop the channel
   */
  async stop(): Promise<void> {
    this.connected = false;
  }

  /**
   * Check if a phone number has access based on dmPolicy
   */
  checkAccess(phone: string): boolean {
    const policy = this.config?.dmPolicy ?? 'open';
    const normalized = this.normalizePhone(phone);

    switch (policy) {
      case 'open':
        return true;

      case 'allowlist':
        return this.allowlist.has(normalized);

      case 'pairing':
        // Pairing mode requires the phone to be in sessions (has messaged before and been approved)
        // For now, treat it similar to allowlist but could integrate with OpenClaw's pairing system
        return this.allowlist.has(normalized) || this.sessions.has(normalized);

      default:
        return true;
    }
  }

  /**
   * Add a phone number to the allowlist
   */
  addToAllowlist(phone: string): void {
    this.allowlist.add(this.normalizePhone(phone));
  }

  /**
   * Remove a phone number from the allowlist
   */
  removeFromAllowlist(phone: string): void {
    this.allowlist.delete(this.normalizePhone(phone));
  }

  /**
   * Get the current allowlist
   */
  getAllowlist(): string[] {
    return Array.from(this.allowlist);
  }

  /**
   * Send a message via the channel
   */
  async sendMessage(envelope: MessageEnvelope): Promise<SendResult> {
    if (!this.config || this.apiClients.size === 0) {
      return {
        success: false,
        error: 'Channel not initialized',
      };
    }

    if (!this.connected) {
      return {
        success: false,
        error: 'Channel not connected',
      };
    }

    const destination = envelope.recipient.id;

    // Get API client (use account from metadata or default)
    const accountName =
      (envelope.metadata?.account as string) ??
      this.config.defaultAccount ??
      this.accounts[0]?.name;

    const apiClient = this.apiClients.get(accountName ?? 'default');
    const account = this.accounts.find((a) => a.name === accountName);

    if (!apiClient || !account) {
      return {
        success: false,
        error: `Account '${accountName}' not found`,
      };
    }

    try {
      // Check session status
      const session = this.getSession(destination);

      if (!session.isActive) {
        // Session expired - need to use template
        return await this.sendTemplateMessage(envelope, destination, apiClient, account);
      }

      // Session active - send regular message
      const gupshupMessage = transformOutbound(envelope);
      const response = await apiClient.sendMessage(destination, gupshupMessage);

      this.lastActivity = Date.now();
      this.probe?.updateActivity(accountName);

      return {
        success: response.status === 'submitted',
        messageId: response.messageId,
        error: response.error?.message,
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      this.lastError = errorMessage;
      this.probe?.markUnhealthy(accountName, errorMessage);

      // Check if session expired error
      if (
        error instanceof Error &&
        'code' in error &&
        (error as { code: string }).code === 'SESSION_EXPIRED'
      ) {
        return await this.sendTemplateMessage(envelope, destination, apiClient, account);
      }

      return {
        success: false,
        error: errorMessage,
      };
    }
  }

  /**
   * Send a template message (for messages outside 24hr session window)
   */
  private async sendTemplateMessage(
    envelope: MessageEnvelope,
    destination: string,
    apiClient: GupshupApiClient,
    account: ResolvedAccount
  ): Promise<SendResult> {
    // Check if templates are configured
    const templates = account.templates;
    if (!templates || Object.keys(templates).length === 0) {
      return {
        success: false,
        error: 'Session expired. No templates configured for out-of-session messaging.',
      };
    }

    // Use first available template (or could be smarter about template selection)
    const templateKey = Object.keys(templates)[0];
    const template = templates[templateKey];

    if (!template) {
      return {
        success: false,
        error: 'Session expired. No valid template found.',
      };
    }

    // Extract text for template params (simple approach)
    const text = envelope.content.text ?? '[Message]';
    const params = template.paramCount ? [text.substring(0, 1024)] : undefined;

    try {
      const response = await apiClient.sendTemplate(destination, template.id, params);

      this.lastActivity = Date.now();
      this.probe?.updateActivity(account.name);

      return {
        success: response.status === 'submitted',
        messageId: response.messageId,
        error: response.error?.message,
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      this.probe?.markUnhealthy(account.name, errorMessage);
      return {
        success: false,
        error: `Template send failed: ${errorMessage}`,
      };
    }
  }

  /**
   * Check if channel is connected
   */
  isConnected(): boolean {
    return this.connected;
  }

  /**
   * Get channel status
   */
  getStatus(): ChannelStatus {
    return {
      connected: this.connected,
      error: this.lastError,
      lastActivity: this.lastActivity,
    };
  }

  /**
   * Get health status (from probe)
   */
  getHealthStatus(): HealthStatus {
    if (!this.probe) {
      return {
        healthy: this.connected,
        channel: CHANNEL_ID,
        accounts: [],
        timestamp: Date.now(),
      };
    }
    return this.probe.getStatus();
  }

  /**
   * Run health check
   */
  async checkHealth(checkApi = false): Promise<HealthStatus> {
    if (!this.probe) {
      return this.getHealthStatus();
    }
    const result = await this.probe.check({ checkApi });
    return result.status;
  }

  /**
   * Get the probe instance (for advanced health management)
   */
  getProbe(): GupshupProbe | null {
    return this.probe;
  }

  /**
   * Get all configured accounts
   */
  getAccounts(): ResolvedAccount[] {
    return [...this.accounts];
  }

  /**
   * Handle incoming webhook request
   * This should be called by the Gateway's HTTP handler
   */
  async handleWebhook(
    body: string,
    signature?: string
  ): Promise<{ status: number; body: string }> {
    if (!this.webhookHandler) {
      return {
        status: 500,
        body: JSON.stringify({ error: 'Webhook handler not initialized' }),
      };
    }

    return this.webhookHandler.handleWebhook(body, signature);
  }

  /**
   * Get the configured webhook path
   */
  getWebhookPath(): string {
    return this.config?.webhookPath ?? '/webhooks/gupshup';
  }

  /**
   * Update session tracking when a message is received
   */
  private updateSession(phone: string): void {
    const normalized = this.normalizePhone(phone);
    this.sessions.set(normalized, {
      phone: normalized,
      lastMessageAt: Date.now(),
      isActive: true,
    });
  }

  /**
   * Get session info for a phone number
   */
  private getSession(phone: string): SessionInfo {
    const normalized = this.normalizePhone(phone);
    const session = this.sessions.get(normalized);

    if (!session) {
      return {
        phone: normalized,
        lastMessageAt: 0,
        isActive: false,
      };
    }

    // Check if session is still active (within 24 hours)
    const now = Date.now();
    const isActive = now - session.lastMessageAt < SESSION_WINDOW_MS;

    return {
      ...session,
      isActive,
    };
  }

  /**
   * Normalize phone number
   */
  private normalizePhone(phone: string): string {
    return phone.replace(/[^\d]/g, '');
  }

  /**
   * Check if a session is active for a given phone number
   */
  isSessionActive(phone: string): boolean {
    return this.getSession(phone).isActive;
  }

  /**
   * Get all active sessions
   */
  getActiveSessions(): SessionInfo[] {
    const now = Date.now();
    const activeSessions: SessionInfo[] = [];

    for (const session of this.sessions.values()) {
      if (now - session.lastMessageAt < SESSION_WINDOW_MS) {
        activeSessions.push({ ...session, isActive: true });
      }
    }

    return activeSessions;
  }

  /**
   * Clear expired sessions (housekeeping)
   */
  clearExpiredSessions(): number {
    const now = Date.now();
    let cleared = 0;

    for (const [phone, session] of this.sessions.entries()) {
      if (now - session.lastMessageAt >= SESSION_WINDOW_MS) {
        this.sessions.delete(phone);
        cleared++;
      }
    }

    return cleared;
  }
}
