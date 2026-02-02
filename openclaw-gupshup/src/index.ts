/**
 * OpenClaw Gupshup WhatsApp Plugin
 *
 * Entry point for the OpenClaw plugin system.
 * Registers the Gupshup channel adapter with the Gateway.
 */

import { GupshupChannel, type GupshupChannelEvents } from './gupshup-channel.js';
import type { GupshupConfig, MessageEnvelope } from './types.js';

// Re-export types for external use
export * from './types.js';
export { GupshupChannel } from './gupshup-channel.js';
export { GupshupApiClient } from './api-client.js';
export { WebhookHandler, createWebhookMiddleware } from './webhook-handler.js';
export { transformInbound, transformOutbound, createTextEnvelope } from './message-transformer.js';
export { resolveAccounts, resolveDefaultAccount, findAccountByPhone, findAccountByName } from './accounts.js';
export { GupshupProbe, createHealthHandler, createDetailedHealthHandler } from './probe.js';

/**
 * Plugin metadata
 */
export const PLUGIN_ID = 'gupshup';
export const PLUGIN_NAME = 'Gupshup WhatsApp';
export const PLUGIN_VERSION = '1.0.0';

/**
 * OpenClaw Plugin Interface
 *
 * This is the main export that OpenClaw's plugin loader looks for.
 * It follows the OpenClaw extension pattern.
 */
export interface OpenClawPlugin {
  id: string;
  name: string;
  version: string;
  activate: (context: PluginContext) => Promise<void>;
  deactivate: () => Promise<void>;
}

/**
 * Plugin context provided by OpenClaw Gateway
 */
export interface PluginContext {
  /** Configuration for this plugin from openclaw.json */
  config: GupshupConfig;
  /** Logger instance */
  logger: Logger;
  /** Register an HTTP route with the Gateway */
  registerHttpRoute: (
    method: 'GET' | 'POST',
    path: string,
    handler: HttpHandler
  ) => void;
  /** Register a channel with the Gateway */
  registerChannel: (channel: ChannelRegistration) => void;
  /** Emit a message to the agent */
  emitMessage: (envelope: MessageEnvelope) => void;
}

export interface Logger {
  debug: (message: string, ...args: unknown[]) => void;
  info: (message: string, ...args: unknown[]) => void;
  warn: (message: string, ...args: unknown[]) => void;
  error: (message: string, ...args: unknown[]) => void;
}

export interface HttpHandler {
  (req: HttpRequest): Promise<HttpResponse>;
}

export interface HttpRequest {
  method: string;
  path: string;
  headers: Record<string, string>;
  body: string;
}

export interface HttpResponse {
  status: number;
  headers?: Record<string, string>;
  body: string;
}

export interface ChannelRegistration {
  id: string;
  name: string;
  sendMessage: (envelope: MessageEnvelope) => Promise<{ success: boolean; messageId?: string; error?: string }>;
  isConnected: () => boolean;
}

// Channel instance (singleton for the plugin lifecycle)
let channelInstance: GupshupChannel | null = null;
let pluginContext: PluginContext | null = null;

/**
 * Activate the plugin
 */
async function activate(context: PluginContext): Promise<void> {
  pluginContext = context;
  const { config, logger, registerHttpRoute, registerChannel, emitMessage } = context;

  logger.info('Activating Gupshup WhatsApp plugin');

  // Validate required configuration (apiKey OR apiKeyFile, and accounts OR single config)
  const hasApiKey = config.apiKey || config.apiKeyFile;
  const hasAccounts = config.accounts && Object.keys(config.accounts).length > 0;

  if (!hasAccounts) {
    // Single account mode - validate top-level config
    if (!hasApiKey) {
      throw new Error('Gupshup API key is required. Set apiKey or apiKeyFile.');
    }
    if (!config.appId) {
      throw new Error('Gupshup App ID is required');
    }
    if (!config.sourcePhone) {
      throw new Error('Gupshup source phone number is required');
    }
  }

  // Create channel instance with event handlers
  const events: GupshupChannelEvents = {
    onMessage: async (envelope) => {
      logger.debug(`Received message from ${envelope.sender.id}`);
      emitMessage(envelope);
    },
    onStatusUpdate: async (event) => {
      logger.debug(`Delivery status: ${event.status} for ${event.messageId}`);
    },
    onUserEvent: async (event) => {
      logger.info(`User event: ${event.type} for ${event.phone}`);
    },
    onAccessDenied: async (phone, policy) => {
      logger.warn(`Access denied for ${phone}. Policy: ${policy}`);
    },
  };

  channelInstance = new GupshupChannel(events);

  // Initialize and start the channel
  await channelInstance.initialize(config);
  await channelInstance.start();

  // Log account info
  const accounts = channelInstance.getAccounts();
  logger.info(`Configured ${accounts.length} account(s): ${accounts.map((a) => a.name).join(', ')}`);

  // Log access control policy
  if (config.dmPolicy && config.dmPolicy !== 'open') {
    logger.info(`Access control: ${config.dmPolicy}`);
    if (config.dmPolicy === 'allowlist' && config.allowFrom) {
      logger.info(`Allowlist: ${config.allowFrom.length} number(s)`);
    }
  }

  // Register HTTP webhook route
  const webhookPath = channelInstance.getWebhookPath();
  logger.info(`Registering webhook at ${webhookPath}`);

  registerHttpRoute('POST', webhookPath, async (req) => {
    if (!channelInstance) {
      return { status: 500, body: JSON.stringify({ error: 'Channel not initialized' }) };
    }

    const signature = req.headers['x-gupshup-signature'] ?? req.headers['x-hub-signature'];
    const result = await channelInstance.handleWebhook(req.body, signature);

    return {
      status: result.status,
      headers: { 'Content-Type': 'application/json' },
      body: result.body,
    };
  });

  // Register health check endpoint
  const healthPath = `${webhookPath}/health`;
  logger.info(`Registering health check at ${healthPath}`);

  registerHttpRoute('GET', healthPath, async () => {
    if (!channelInstance) {
      return {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ healthy: false, error: 'Channel not initialized' }),
      };
    }

    const health = await channelInstance.checkHealth(false);
    return {
      status: health.healthy ? 200 : 503,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(health, null, 2),
    };
  });

  // Register channel with Gateway
  registerChannel({
    id: PLUGIN_ID,
    name: PLUGIN_NAME,
    sendMessage: (envelope) => channelInstance!.sendMessage(envelope),
    isConnected: () => channelInstance?.isConnected() ?? false,
  });

  logger.info('Gupshup WhatsApp plugin activated successfully');
}

/**
 * Deactivate the plugin
 */
async function deactivate(): Promise<void> {
  if (pluginContext) {
    pluginContext.logger.info('Deactivating Gupshup WhatsApp plugin');
  }

  if (channelInstance) {
    await channelInstance.stop();
    channelInstance = null;
  }

  pluginContext = null;
}

/**
 * Plugin export for OpenClaw
 */
const plugin: OpenClawPlugin = {
  id: PLUGIN_ID,
  name: PLUGIN_NAME,
  version: PLUGIN_VERSION,
  activate,
  deactivate,
};

export default plugin;

/**
 * Factory function for standalone usage (testing, custom integrations)
 */
export function createGupshupChannel(
  config: GupshupConfig,
  events?: GupshupChannelEvents
): GupshupChannel {
  const channel = new GupshupChannel(events);
  // Note: caller must call initialize() and start()
  return channel;
}
