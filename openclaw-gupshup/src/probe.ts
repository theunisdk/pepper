/**
 * Health Probe
 *
 * Provides health check functionality for monitoring the Gupshup channel.
 */

import { request } from 'undici';
import type { GupshupConfig, HealthStatus, AccountHealthStatus, ResolvedAccount } from './types.js';
import { resolveAccounts } from './accounts.js';

const GUPSHUP_HEALTH_ENDPOINT = 'https://api.gupshup.io/wa/api/v1/health';
const PROBE_TIMEOUT = 10000; // 10 seconds

export interface ProbeOptions {
  /** Timeout in milliseconds */
  timeout?: number;
  /** Whether to check API connectivity (makes HTTP request) */
  checkApi?: boolean;
}

export interface ProbeResult {
  status: HealthStatus;
  details?: string;
}

/**
 * Health probe for the Gupshup channel
 */
export class GupshupProbe {
  private readonly config: GupshupConfig;
  private readonly accounts: ResolvedAccount[];
  private accountStatuses: Map<string, AccountHealthStatus> = new Map();

  constructor(config: GupshupConfig) {
    this.config = config;
    this.accounts = resolveAccounts(config);

    // Initialize account statuses
    for (const account of this.accounts) {
      this.accountStatuses.set(account.name, {
        name: account.name,
        phoneNumber: account.phoneNumber,
        connected: false,
      });
    }
  }

  /**
   * Run health check
   */
  async check(options: ProbeOptions = {}): Promise<ProbeResult> {
    const { timeout = PROBE_TIMEOUT, checkApi = true } = options;

    const accountResults: AccountHealthStatus[] = [];

    for (const account of this.accounts) {
      const status = await this.checkAccount(account, { timeout, checkApi });
      this.accountStatuses.set(account.name, status);
      accountResults.push(status);
    }

    const allHealthy = accountResults.every((a) => a.connected);
    const anyHealthy = accountResults.some((a) => a.connected);

    return {
      status: {
        healthy: anyHealthy,
        channel: 'gupshup',
        accounts: accountResults,
        timestamp: Date.now(),
      },
      details: allHealthy
        ? 'All accounts healthy'
        : anyHealthy
          ? 'Some accounts unhealthy'
          : 'All accounts unhealthy',
    };
  }

  /**
   * Check a single account
   */
  private async checkAccount(
    account: ResolvedAccount,
    options: { timeout: number; checkApi: boolean }
  ): Promise<AccountHealthStatus> {
    const existing = this.accountStatuses.get(account.name);

    if (!options.checkApi) {
      // Return cached status without API check
      return existing ?? {
        name: account.name,
        phoneNumber: account.phoneNumber,
        connected: false,
        error: 'Not checked',
      };
    }

    try {
      // Try to verify API key by making a lightweight request
      // Gupshup doesn't have a dedicated health endpoint, so we'll do a simple auth check
      const response = await request(GUPSHUP_HEALTH_ENDPOINT, {
        method: 'GET',
        headers: {
          'apikey': account.apiKey,
        },
        bodyTimeout: options.timeout,
        headersTimeout: options.timeout,
      });

      // Any 2xx or even 404 (endpoint might not exist) with valid auth is OK
      // 401/403 means bad API key
      const isHealthy = response.statusCode !== 401 && response.statusCode !== 403;

      return {
        name: account.name,
        phoneNumber: account.phoneNumber,
        connected: isHealthy,
        lastActivity: existing?.lastActivity,
        error: isHealthy ? undefined : 'Authentication failed',
      };
    } catch (error) {
      return {
        name: account.name,
        phoneNumber: account.phoneNumber,
        connected: false,
        lastActivity: existing?.lastActivity,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Update last activity timestamp for an account
   */
  updateActivity(accountName: string): void {
    const status = this.accountStatuses.get(accountName);
    if (status) {
      status.lastActivity = Date.now();
      status.connected = true;
      status.error = undefined;
    }
  }

  /**
   * Mark an account as unhealthy
   */
  markUnhealthy(accountName: string, error: string): void {
    const status = this.accountStatuses.get(accountName);
    if (status) {
      status.connected = false;
      status.error = error;
    }
  }

  /**
   * Get current status without making API calls
   */
  getStatus(): HealthStatus {
    const accounts = Array.from(this.accountStatuses.values());
    const anyHealthy = accounts.some((a) => a.connected);

    return {
      healthy: anyHealthy,
      channel: 'gupshup',
      accounts,
      timestamp: Date.now(),
    };
  }

  /**
   * Get status for a specific account
   */
  getAccountStatus(accountName: string): AccountHealthStatus | undefined {
    return this.accountStatuses.get(accountName);
  }
}

/**
 * Create a simple health check handler for HTTP endpoints
 */
export function createHealthHandler(probe: GupshupProbe): () => Promise<{
  status: number;
  body: string;
}> {
  return async () => {
    const result = await probe.check({ checkApi: false });

    return {
      status: result.status.healthy ? 200 : 503,
      body: JSON.stringify(result.status, null, 2),
    };
  };
}

/**
 * Create a detailed health check handler (with API verification)
 */
export function createDetailedHealthHandler(probe: GupshupProbe): () => Promise<{
  status: number;
  body: string;
}> {
  return async () => {
    const result = await probe.check({ checkApi: true });

    return {
      status: result.status.healthy ? 200 : 503,
      body: JSON.stringify(
        {
          ...result.status,
          details: result.details,
        },
        null,
        2
      ),
    };
  };
}
