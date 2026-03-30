'use strict';

const logger = require('../config/logger');

const AT_API = 'https://api.africastalking.com/version1/messaging';

/**
 * Send a plain-text SMS via Africa's Talking.
 * @param {string} to   - E.164 phone number, e.g. +254712345678
 * @param {string} body - Message text
 * @returns {Promise<boolean>} true if AT accepted (HTTP 201)
 */
async function sendSms(to, body) {
  const params = new URLSearchParams({
    username: process.env.AT_USERNAME,
    to,
    message: body,
    bulkSMSMode: '1',
  });

  // Use registered sender ID once approved; omit for shared shortcode
  if (process.env.AT_SENDER_ID) {
    params.set('from', process.env.AT_SENDER_ID);
  }

  try {
    const res = await fetch(AT_API, {
      method: 'POST',
      headers: {
        apiKey:          process.env.AT_API_KEY,
        Accept:          'application/json',
        'Content-Type':  'application/x-www-form-urlencoded',
      },
      body: params.toString(),
      signal: AbortSignal.timeout(15000),
    });

    if (res.status !== 201) {
      const text = await res.text().catch(() => '');
      logger.warn('Africa\'s Talking SMS rejected', { status: res.status, to, body: text });
      return false;
    }

    logger.info('SMS sent via Africa\'s Talking', { to });
    return true;
  } catch (err) {
    logger.error('Africa\'s Talking SMS error', { to, error: err.message });
    return false;
  }
}

module.exports = { sendSms };
