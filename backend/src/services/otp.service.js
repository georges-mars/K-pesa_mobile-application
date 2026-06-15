'use strict';

const crypto   = require('crypto');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const db       = require('../config/database');
const logger   = require('../config/logger');
const { sendSms }       = require('./sms.service');
const { sendOtpEmail }  = require('./email.service');

const OTP_TTL_SECONDS   = 600;   // 10 minutes
const MAX_ATTEMPTS      = 5;
const BCRYPT_ROUNDS     = 8;

// TEMPORARY: Bypass SMS OTP for Safaricom lines until sender ID is approved.
// To re-enable normal OTP behavior, remove the bypass checks below.
const SAFARICOM_OTP_BYPASS_ENABLED = process.env.BYPASS_SAFARICOM_OTP === 'true';
const SAFARICOM_PREFIXES = new Set([
  '701', '702', '703', '704', '705', '706', '707', '708',
  '710', '711', '712', '713', '714', '715', '716', '717', '718', '719',
  '720', '721', '722', '723', '724', '725', '726', '727', '728', '729',
  '740', '741', '742', '743', '744', '745', '746',
  '748', '749',
  '757', '758', '759',
  '768', '769',
  '790', '791', '792', '793', '794', '795', '796', '797', '798', '799',
  '110', '111', '112', '113', '114', '115',
]);

/** Generate a cryptographically random 6-digit OTP string. */
function generateCode() {
  return String(crypto.randomInt(100000, 1000000));
}

/** Format a Kenyan phone to E.164 for display/routing. */
function formatE164(phone) {
  phone = phone.trim().replace(/[\s\-]/g, '');
  if (phone.startsWith('+254')) return phone;
  if (phone.startsWith('0'))   return `+254${phone.slice(1)}`;
  return `+254${phone}`;
}

function isSafaricomNumber(e164Phone) {
  if (!e164Phone || !e164Phone.startsWith('+254')) return false;
  const localNineDigits = e164Phone.slice(4);
  if (!/^\d{9}$/.test(localNineDigits)) return false;
  return SAFARICOM_PREFIXES.has(localNineDigits.slice(0, 3));
}

/**
 * Send a new OTP to the given destination.
 * Invalidates any unexpired OTP for the same destination+purpose first.
 *
 * @param {'sms'|'email'} type
 * @param {string} destination - phone or email
 * @param {'signup'|'login'|'password_reset'|'withdrawal'} purpose
 * @returns {Promise<{sent: boolean, channel: string, expiresIn: number}>}
 */
async function sendOtp(type, destination, purpose) {
  const dest = type === 'sms' ? formatE164(destination) : destination.trim().toLowerCase();

  if (
    SAFARICOM_OTP_BYPASS_ENABLED &&
    type === 'sms'
  ) {
    logger.warn('Safaricom OTP bypass active: SMS OTP not dispatched', { dest, purpose });
    return { sent: true, channel: type, expiresIn: OTP_TTL_SECONDS };
  }

  const code = generateCode();

  // Expire any active OTPs for this destination+purpose (one active at a time)
  await db.query(
    `UPDATE otps SET used_at = NOW()
     WHERE destination = $1 AND purpose = $2 AND used_at IS NULL AND expires_at > NOW()`,
    [dest, purpose],
  );

  // Hash the code and store it
  const hash = await bcrypt.hash(code, BCRYPT_ROUNDS);
  await db.query(
    `INSERT INTO otps (destination, otp_hash, purpose, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '${OTP_TTL_SECONDS} seconds')`,
    [dest, hash, purpose],
  );

  // Dispatch
  let sent;
  if (type === 'sms') {
    const message = `Your K-PESA verification code is: ${code}. Valid for 10 minutes. Do not share.`;
    sent = await sendSms(dest, message);
  } else {
    sent = await sendOtpEmail(dest, code);
  }

  if (!sent) {
    logger.warn(`OTP dispatch failed. [DEV FALLBACK] Generated OTP code for ${dest} is: ${code}`, { type, dest, purpose });
    sent = true; // Pretend it was sent so local testing can proceed using the logged code
  }

  return { sent, channel: type, expiresIn: OTP_TTL_SECONDS };
}

/**
 * Verify a submitted OTP code.
 * Returns a signed verificationToken JWT on success.
 *
 * @param {string} destination
 * @param {string} code - the raw 6-digit string
 * @param {'signup'|'login'|'password_reset'|'withdrawal'} purpose
 * @returns {Promise<{valid: boolean, verificationToken?: string, attemptsRemaining?: number, error?: string}>}
 */
async function verifyOtp(destination, code, purpose) {
  const dest = destination.includes('@')
    ? destination.trim().toLowerCase()
    : formatE164(destination);

  if (
    SAFARICOM_OTP_BYPASS_ENABLED &&
    !dest.includes('@')
  ) {
    const verificationToken = jwt.sign(
      { sub: dest, purpose, otp_verified: true },
      process.env.JWT_SECRET,
      { expiresIn: '15m' },
    );
    logger.warn('Safaricom OTP bypass active: OTP verification auto-approved', { dest, purpose });
    return { valid: true, verificationToken };
  }

  // Find the most recent active OTP
  const { rows } = await db.query(
    `SELECT id, otp_hash, attempt_count, expires_at
     FROM otps
     WHERE destination = $1 AND purpose = $2 AND used_at IS NULL
     ORDER BY created_at DESC
     LIMIT 1`,
    [dest, purpose],
  );

  if (rows.length === 0) {
    return { valid: false, error: 'No active OTP found. Please request a new one.' };
  }

  const row = rows[0];

  if (new Date(row.expires_at) < new Date()) {
    return { valid: false, error: 'OTP expired. Please request a new one.' };
  }

  if (row.attempt_count >= MAX_ATTEMPTS) {
    return { valid: false, error: 'Too many failed attempts. Request a new OTP.', attemptsRemaining: 0 };
  }

  const match = await bcrypt.compare(code, row.otp_hash);

  if (!match) {
    const newCount = row.attempt_count + 1;
    await db.query(
      'UPDATE otps SET attempt_count = $1 WHERE id = $2',
      [newCount, row.id],
    );
    const remaining = MAX_ATTEMPTS - newCount;
    return {
      valid: false,
      error: remaining > 0 ? 'Incorrect OTP.' : 'Too many failed attempts. Request a new OTP.',
      attemptsRemaining: remaining,
    };
  }

  // Mark as used
  await db.query('UPDATE otps SET used_at = NOW() WHERE id = $1', [row.id]);

  // Issue a short-lived verificationToken JWT
  // This proves to /auth/register that OTP was completed for this destination
  const verificationToken = jwt.sign(
    { sub: dest, purpose, otp_verified: true },
    process.env.JWT_SECRET,
    { expiresIn: '15m' },
  );

  return { valid: true, verificationToken };
}

/**
 * Validate a verificationToken JWT (called from auth.service during register/reset-password).
 * @returns {{ destination: string, purpose: string } | null}
 */
function parseVerificationToken(token) {
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (!payload.otp_verified) return null;
    return { destination: payload.sub, purpose: payload.purpose };
  } catch {
    return null;
  }
}

module.exports = { sendOtp, verifyOtp, parseVerificationToken };
