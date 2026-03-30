'use strict';

const logger = require('../config/logger');

// Simple in-memory cache for exchange rates
let cache = {
  buyRate:  133.65,  // KES per 1 USD (deposit rate — user buys USD)
  sellRate: 124.08,  // KES per 1 USD (withdrawal rate — user sells USD)
  updatedAt: 0,
};

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Refresh KES/USD rates from an open currency API.
 * Falls back to hardcoded defaults if the fetch fails.
 */
async function refreshRates() {
  try {
    const res = await fetch(
      'https://api.exchangerate-api.com/v4/latest/USD',
      { signal: AbortSignal.timeout(8000) },
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const mid = data.rates?.KES;
    if (mid && mid > 0) {
      // Apply ±2% spread around mid rate
      cache.buyRate  = parseFloat((mid * 1.02).toFixed(5));
      cache.sellRate = parseFloat((mid * 0.98).toFixed(5));
      cache.updatedAt = Date.now();
      logger.debug('Forex rates refreshed', { mid, buy: cache.buyRate, sell: cache.sellRate });
    }
  } catch (err) {
    logger.warn('Forex rate refresh failed, using cached/default', { error: err.message });
  }
}

/**
 * Returns current buy/sell KES/USD rates, refreshing if stale.
 */
async function getRates() {
  if (Date.now() - cache.updatedAt > CACHE_TTL_MS) {
    await refreshRates();
  }
  return { buyRate: cache.buyRate, sellRate: cache.sellRate };
}

/** KES → USD using the buy rate (user deposits KES, receives USD) */
async function kesToUsd(amountKes) {
  const { buyRate } = await getRates();
  return { usd: parseFloat((amountKes / buyRate).toFixed(4)), rate: buyRate };
}

/** USD → KES using the sell rate (user withdraws KES, sells USD) */
async function usdToKes(amountUsd) {
  const { sellRate } = await getRates();
  return { kes: parseFloat((amountUsd * sellRate).toFixed(2)), rate: sellRate };
}

module.exports = { getRates, kesToUsd, usdToKes };
