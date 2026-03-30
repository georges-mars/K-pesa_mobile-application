'use strict';

const WebSocket = require('ws');
const db        = require('../config/database');
const logger    = require('../config/logger');
const cryptoService = require('./crypto.service');

const WS_URL = 'wss://ws.derivws.com/websockets/v3';

// Simple in-memory balance cache (per user, 60 second TTL)
const balanceCache = new Map(); // userId → { deriv, mt5, cachedAt }
const CACHE_TTL_MS = 60_000;

/**
 * Authorize a Deriv API token via WebSocket and return the account profile.
 * Deriv OAuth redirects with token1/acct1 directly — no code exchange needed.
 */
function authorizeToken(derivToken) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS_URL}?app_id=${process.env.DERIV_APP_ID}`);
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error('Deriv connection timed out'));
    }, 10_000);

    ws.on('open', () => {
      ws.send(JSON.stringify({ authorize: derivToken }));
    });

    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      clearTimeout(timer);
      ws.close();

      if (msg.error) {
        return reject(new Error(msg.error.message));
      }
      if (msg.msg_type === 'authorize') {
        const auth = msg.authorize;
        resolve({
          name:    auth.fullname  || null,
          email:   auth.email     || null,
          account: auth.loginid   || null,
          hasLiveAccount: typeof auth.loginid === 'string' && auth.loginid.startsWith('CR'),
        });
      }
    });

    ws.on('error', (err) => { clearTimeout(timer); reject(err); });
  });
}

/**
 * Verify a Deriv token and return the account profile.
 * If userId is provided, also persist the token in the database.
 *
 * Called during signup (no userId) to pre-fill the signup form,
 * and after login (with userId) to store/update the linked account.
 */
async function connectAccount(derivToken, derivAccount, userId = null) {
  let profile;
  try {
    profile = await authorizeToken(derivToken);
  } catch (err) {
    logger.warn('Deriv token verification failed', { error: err.message });
    const e = new Error('Invalid Deriv token. Please log in with Deriv again.');
    e.type = 'VALIDATION';
    throw e;
  }

  // Persist only when we have a logged-in K-Pesa user
  if (userId) {
    // Encrypt the Deriv token before storing
    const { ciphertext: encryptedToken, keyVersion } = await cryptoService.encrypt('external', derivToken);
    
    await db.query(
      `UPDATE users
          SET deriv_access_token = $1, deriv_account = $2, ext_key_version = $3
        WHERE id = $4`,
      [encryptedToken, derivAccount || profile.account, keyVersion, userId],
    );
  }

  return { profile };
}

/**
 * Fetch live Deriv + MT5 balances for a user.
 * Uses cached values if fresh enough.
 */
async function getBalances(userId) {
  const cached = balanceCache.get(userId);
  if (cached && Date.now() - cached.cachedAt < CACHE_TTL_MS) {
    return { ...cached, cached: true };
  }

  const { rows } = await db.query(
    `SELECT deriv_access_token, ext_key_version FROM users WHERE id = $1`,
    [userId],
  );

  const user = rows[0];
  if (!user || !user.deriv_access_token) {
    return { deriv: null, mt5: null, cached: false };
  }

  // Decrypt the Deriv token
  const decryptedToken = await cryptoService.decrypt(
    'external', 
    user.deriv_access_token, 
    user.ext_key_version
  );

  let derivBalance = null;
  let mt5Balance   = null;

  try {
    const result = await fetchBalancesViaWS(decryptedToken);
    derivBalance = result.deriv;
    mt5Balance   = result.mt5;
  } catch (err) {
    logger.warn('Deriv balance fetch failed', { userId, error: err.message });
  }

  const payload = { deriv: derivBalance, mt5: mt5Balance, cachedAt: Date.now(), cached: false };
  balanceCache.set(userId, payload);
  return payload;
}

/**
 * Fetch Deriv + MT5 balances via WebSocket.
 */
function fetchBalancesViaWS(derivToken) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS_URL}?app_id=${process.env.DERIV_APP_ID}`);
    const result = { deriv: null, mt5: null };
    const timer = setTimeout(() => { ws.close(); reject(new Error('Deriv WS timeout')); }, 10_000);

    ws.on('open', () => {
      ws.send(JSON.stringify({ authorize: derivToken }));
    });

    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());

      if (msg.error) {
        clearTimeout(timer);
        ws.close();
        return reject(new Error(msg.error.message));
      }
      if (msg.msg_type === 'authorize') {
        ws.send(JSON.stringify({ balance: 1, account: 'all' }));
      }
      if (msg.msg_type === 'balance') {
        const bal = msg.balance;
        if (bal.account_type === 'deriv') {
          result.deriv = { balance: bal.balance, currency: bal.currency };
        } else if (bal.account_type === 'mt5') {
          result.mt5 = { balance: bal.balance, currency: bal.currency };
        }
        clearTimeout(timer);
        ws.close();
        resolve(result);
      }
    });

    ws.on('error', (err) => { clearTimeout(timer); reject(err); });
  });
}

module.exports = { connectAccount, getBalances };
