'use strict';

const logger = require('../config/logger');

// ── Daraja URLs ───────────────────────────────────────────────────────────────
const env = () => process.env.MPESA_ENV === 'production' ? 'production' : 'sandbox';

const DARAJA_BASE = () =>
  env() === 'production'
    ? 'https://api.safaricom.co.ke'
    : 'https://sandbox.safaricom.co.ke';

// ── Access token cache ────────────────────────────────────────────────────────
let cachedToken    = null;
let tokenExpiresAt = 0;

async function getAccessToken() {
  if (cachedToken && Date.now() < tokenExpiresAt) return cachedToken;

  const credentials = Buffer.from(
    `${process.env.MPESA_CONSUMER_KEY}:${process.env.MPESA_CONSUMER_SECRET}`,
  ).toString('base64');

  const res = await fetch(
    `${DARAJA_BASE()}/oauth/v1/generate?grant_type=client_credentials`,
    {
      headers: { Authorization: `Basic ${credentials}` },
      signal:  AbortSignal.timeout(10000),
    },
  );

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Daraja OAuth failed: ${res.status} ${text}`);
  }

  const data = await res.json();
  cachedToken    = data.access_token;
  tokenExpiresAt = Date.now() + (parseInt(data.expires_in) - 60) * 1000;
  return cachedToken;
}

// ── STK Push (deposit) ────────────────────────────────────────────────────────

/**
 * Initiate an M-Pesa STK Push payment prompt.
 * @param {string}  phone       - E.164 phone number e.g. +254712345678
 * @param {number}  amountKes   - Integer amount in KES
 * @param {string}  reference   - AccountReference shown on the STK Push
 * @returns {Promise<{ checkoutRequestId: string }>}
 */
async function stkPush(phone, amountKes, reference) {
  const token     = await getAccessToken();
  const timestamp = new Date().toISOString().replace(/[^0-9]/g, '').slice(0, 14);
  const password  = Buffer.from(
    `${process.env.MPESA_SHORT_CODE}${process.env.MPESA_PASSKEY}${timestamp}`,
  ).toString('base64');

  const payload = {
    BusinessShortCode: process.env.MPESA_SHORT_CODE,
    Password:          password,
    Timestamp:         timestamp,
    TransactionType:   'CustomerPayBillOnline',
    Amount:            Math.ceil(amountKes),
    PartyA:            phone,
    PartyB:            process.env.MPESA_SHORT_CODE,
    PhoneNumber:       phone,
    CallBackURL:       `${process.env.BASE_URL}/api/v1/callbacks/mpesa/stk`,
    AccountReference:  reference,
    TransactionDesc:   'K-PESA Deposit',
  };

  const res = await fetch(`${DARAJA_BASE()}/mpesa/stkpush/v1/processrequest`, {
    method:  'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body:    JSON.stringify(payload),
    signal:  AbortSignal.timeout(15000),
  });

  const data = await res.json();
  logger.debug('STK Push response', { data });

  if (data.ResponseCode !== '0') {
    throw new Error(data.ResponseDescription || 'STK Push failed');
  }

  return { checkoutRequestId: data.CheckoutRequestID };
}

// ── B2C (withdrawal) ──────────────────────────────────────────────────────────

/**
 * Initiate an M-Pesa B2C payment (business to customer).
 * @param {string}  phone         - E.164 recipient
 * @param {number}  amountKes     - Integer KES amount
 * @param {string}  originatorId  - Our transactionId used as correlation key
 * @returns {Promise<{ conversationId: string }>}
 */
async function b2cPay(phone, amountKes, originatorId) {
  const token = await getAccessToken();

  const payload = {
    OriginatorConversationID: originatorId,
    InitiatorName:            process.env.MPESA_INITIATOR_NAME,
    SecurityCredential:       process.env.MPESA_SECURITY_CREDENTIAL,
    CommandID:                'BusinessPayment',
    Amount:                   Math.floor(amountKes),
    PartyA:                   process.env.MPESA_SHORT_CODE,
    PartyB:                   phone,
    Remarks:                  'K-PESA Withdrawal',
    QueueTimeOutURL:          `${process.env.BASE_URL}/api/v1/callbacks/mpesa/b2c/timeout`,
    ResultURL:                `${process.env.BASE_URL}/api/v1/callbacks/mpesa/b2c/result`,
    Occasion:                 'KPESAWithdrawal',
  };

  const res = await fetch(`${DARAJA_BASE()}/mpesa/b2c/v3/paymentrequest`, {
    method:  'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body:    JSON.stringify(payload),
    signal:  AbortSignal.timeout(15000),
  });

  const data = await res.json();
  logger.debug('B2C response', { data });

  if (data.ResponseCode !== '0') {
    throw new Error(data.ResponseDescription || 'B2C payment failed');
  }

  return { conversationId: data.ConversationID };
}

module.exports = { stkPush, b2cPay, getAccessToken };
