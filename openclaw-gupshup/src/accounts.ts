/**
 * Account Resolution
 *
 * Handles multi-account configuration and API key loading from files.
 */

import { readFileSync } from 'fs';
import type { GupshupConfig, GupshupAccountConfig, ResolvedAccount } from './types.js';

const DEFAULT_BUSINESS_NAME = 'Assistant';

/**
 * Resolve all accounts from configuration
 */
export function resolveAccounts(config: GupshupConfig): ResolvedAccount[] {
  const accounts: ResolvedAccount[] = [];

  // If multi-account mode (accounts object defined)
  if (config.accounts && Object.keys(config.accounts).length > 0) {
    for (const [name, accountConfig] of Object.entries(config.accounts)) {
      const resolved = resolveAccount(name, accountConfig, config);
      accounts.push(resolved);
    }
  } else {
    // Single account mode - use top-level config
    const resolved = resolveSingleAccount(config);
    accounts.push(resolved);
  }

  return accounts;
}

/**
 * Resolve the default account
 */
export function resolveDefaultAccount(config: GupshupConfig): ResolvedAccount {
  const accounts = resolveAccounts(config);

  if (accounts.length === 0) {
    throw new Error('No accounts configured');
  }

  // If defaultAccount specified, find it
  if (config.defaultAccount) {
    const account = accounts.find((a) => a.name === config.defaultAccount);
    if (!account) {
      throw new Error(`Default account '${config.defaultAccount}' not found`);
    }
    return account;
  }

  // Otherwise return first account
  return accounts[0];
}

/**
 * Find account by phone number
 */
export function findAccountByPhone(
  config: GupshupConfig,
  phoneNumber: string
): ResolvedAccount | undefined {
  const accounts = resolveAccounts(config);
  const normalized = normalizePhone(phoneNumber);
  return accounts.find((a) => normalizePhone(a.phoneNumber) === normalized);
}

/**
 * Find account by name
 */
export function findAccountByName(
  config: GupshupConfig,
  name: string
): ResolvedAccount | undefined {
  const accounts = resolveAccounts(config);
  return accounts.find((a) => a.name === name);
}

/**
 * Resolve a single named account
 */
function resolveAccount(
  name: string,
  accountConfig: GupshupAccountConfig,
  parentConfig: GupshupConfig
): ResolvedAccount {
  // API key: account-level > parent-level
  const apiKey = loadApiKey(
    accountConfig.apiKey ?? parentConfig.apiKey,
    accountConfig.apiKeyFile ?? parentConfig.apiKeyFile
  );

  if (!apiKey) {
    throw new Error(`No API key configured for account '${name}'`);
  }

  if (!accountConfig.appId) {
    throw new Error(`No appId configured for account '${name}'`);
  }

  if (!accountConfig.phoneNumber) {
    throw new Error(`No phoneNumber configured for account '${name}'`);
  }

  return {
    name,
    apiKey,
    appId: accountConfig.appId,
    phoneNumber: accountConfig.phoneNumber,
    businessName: accountConfig.businessName ?? parentConfig.businessName ?? DEFAULT_BUSINESS_NAME,
    webhookSecret: accountConfig.webhookSecret ?? parentConfig.webhookSecret,
    templates: { ...parentConfig.templates, ...accountConfig.templates },
  };
}

/**
 * Resolve single-account mode configuration
 */
function resolveSingleAccount(config: GupshupConfig): ResolvedAccount {
  const apiKey = loadApiKey(config.apiKey, config.apiKeyFile);

  if (!apiKey) {
    throw new Error('No API key configured. Set apiKey or apiKeyFile.');
  }

  if (!config.appId) {
    throw new Error('No appId configured');
  }

  if (!config.sourcePhone) {
    throw new Error('No sourcePhone configured');
  }

  return {
    name: 'default',
    apiKey,
    appId: config.appId,
    phoneNumber: config.sourcePhone,
    businessName: config.businessName ?? DEFAULT_BUSINESS_NAME,
    webhookSecret: config.webhookSecret,
    templates: config.templates,
  };
}

/**
 * Load API key from value or file
 */
function loadApiKey(apiKey?: string, apiKeyFile?: string): string | undefined {
  // Direct value takes precedence
  if (apiKey) {
    return apiKey;
  }

  // Try loading from file
  if (apiKeyFile) {
    try {
      const expanded = expandPath(apiKeyFile);
      const content = readFileSync(expanded, 'utf-8');
      return content.trim();
    } catch (error) {
      throw new Error(
        `Failed to read API key from file '${apiKeyFile}': ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }

  return undefined;
}

/**
 * Expand ~ and environment variables in path
 */
function expandPath(filePath: string): string {
  // Expand ~
  if (filePath.startsWith('~/')) {
    const home = process.env.HOME ?? process.env.USERPROFILE ?? '';
    return filePath.replace('~', home);
  }

  // Expand $VAR and ${VAR}
  return filePath.replace(/\$\{?(\w+)\}?/g, (_, varName) => {
    return process.env[varName] ?? '';
  });
}

/**
 * Normalize phone number for comparison
 */
function normalizePhone(phone: string): string {
  return phone.replace(/[^\d]/g, '');
}
