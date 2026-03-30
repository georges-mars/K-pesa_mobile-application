'use strict';

const crypto   = require('crypto');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const db       = require('../config/database');
const logger   = require('../config/logger');
const { parseVerificationToken } = require('./otp.service');
const cryptoService = require('./crypto.service');

const BCRYPT_ROUNDS = 12;
const REFRESH_DAYS  = parseInt(process.env.REFRESH_TOKEN_EXPIRES_DAYS || '7');

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Generate a random referral code like KPESA-AB12CD */
function generateReferralCode() {
  return 'KPESA-' + crypto.randomBytes(3).toString('hex').toUpperCase();
}

/** Issue a JWT access token. */
function signAccessToken(userId, email) {
  return jwt.sign(
    { sub: userId, email },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '15m' },
  );
}

/** Issue an opaque refresh token, store its hash in DB, return raw token. */
async function issueRefreshToken(userId, ip) {
  const raw  = crypto.randomBytes(40).toString('hex');
  const hash = crypto.createHash('sha256').update(raw).digest('hex');
  const exp  = new Date();
  exp.setDate(exp.getDate() + REFRESH_DAYS);

  await db.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, ip_address, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [userId, hash, ip || null, exp],
  );
  return raw;
}

// ── Register ──────────────────────────────────────────────────────────────────

/**
 * Create a new user account.
 * Verifies the OTP verificationToken before writing to DB.
 */
async function register(body, ip) {
  const {
    email, password, verificationToken,
    fullName, derivEmail, derivName, derivAccount, binanceId,
    mpesaPhone, airtelPhone, bankName, bankAccountName, bankAccountNumber,
    affiliateCode,
  } = body;

  // 1. Validate verificationToken
  const verified = parseVerificationToken(verificationToken);
  if (!verified || verified.purpose !== 'signup') {
    const err = new Error('Invalid or expired verification token. Complete OTP first.');
    err.type = 'VALIDATION';
    throw err;
  }

  // 2. Check email not already taken
  const existing = await db.query('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
  if (existing.rows.length > 0) {
    const err = new Error('An account with this email already exists.');
    err.type = 'CONFLICT';
    throw err;
  }

  // 3. Hash password
  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

  // 4. Generate unique referral code
  let referralCode;
  for (let i = 0; i < 5; i++) {
    const candidate = generateReferralCode();
    const check = await db.query('SELECT id FROM users WHERE referral_code = $1', [candidate]);
    if (check.rows.length === 0) { referralCode = candidate; break; }
  }

  // 5. Resolve affiliate referrer
  let referredBy = null;
  if (affiliateCode) {
    const ref = await db.query('SELECT id FROM users WHERE referral_code = $1', [affiliateCode.trim().toUpperCase()]);
    if (ref.rows.length > 0) referredBy = ref.rows[0].id;
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // 6. Insert user with encrypted full_name
    const { ciphertext: encryptedName, keyVersion: piiKeyVersion } = await cryptoService.encrypt('user_pii', fullName);
    
    const userResult = await client.query(
      `INSERT INTO users
         (email, password_hash, full_name, deriv_email, deriv_name, deriv_account,
          binance_id, referral_code, referred_by, is_verified, pii_key_version)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE,$10)
       RETURNING id`,
      [
        email.toLowerCase(), passwordHash, encryptedName,
        derivEmail || null, derivName || null, derivAccount || null,
        binanceId || null, referralCode, referredBy, piiKeyVersion,
      ],
    );
    const userId = userResult.rows[0].id;

    // 7. Insert payment methods with encryption
    const pm = [];
    if (mpesaPhone)  pm.push({ type: 'mpesa',  phone: mpesaPhone,  isDefault: true });
    if (airtelPhone) pm.push({ type: 'airtel', phone: airtelPhone, isDefault: !mpesaPhone });
    if (bankName)    pm.push({ type: 'bank',   bankName, bankAccountName, bankAccountNumber, isDefault: !mpesaPhone && !airtelPhone });

    for (const m of pm) {
      // Encrypt sensitive fields (only if they have values)
      let payKeyVersion = null;
      
      const { ciphertext: encPhone, keyVersion: phoneKeyVersion } = m.phone 
        ? await cryptoService.encrypt('payment', m.phone) 
        : { ciphertext: null, keyVersion: null };
      
      const { ciphertext: encAcctName, keyVersion: nameKeyVersion } = m.bankAccountName 
        ? await cryptoService.encrypt('payment', m.bankAccountName) 
        : { ciphertext: null, keyVersion: null };
      
      const { ciphertext: encAcctNum, keyVersion: numKeyVersion } = m.bankAccountNumber 
        ? await cryptoService.encrypt('payment', m.bankAccountNumber) 
        : { ciphertext: null, keyVersion: null };
      
      // Use any non-null key version (they should all be the same for active DEK)
      payKeyVersion = phoneKeyVersion || nameKeyVersion || numKeyVersion;
      
      // Generate HMAC for searchable fields (only if they have values)
      const phoneHmac = m.phone ? await cryptoService.hmacField(m.phone) : null;
      const acctHmac = m.bankAccountNumber ? await cryptoService.hmacField(m.bankAccountNumber) : null;
      
      await client.query(
        `INSERT INTO payment_methods
           (user_id, type, phone_number, bank_name, account_name, account_number, 
            phone_number_hmac, account_number_hmac, key_version, is_default)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
        [
          userId, m.type,
          encPhone,
          m.bankName || null,
          encAcctName,
          encAcctNum,
          phoneHmac,
          acctHmac,
          payKeyVersion, // Can be null if no fields were encrypted
          m.isDefault,
        ],
      );
    }

    // 8. Record affiliate redemption
    if (referredBy) {
      await client.query(
        `INSERT INTO affiliate_redemptions (referrer_id, referee_id, referral_code)
         VALUES ($1,$2,$3) ON CONFLICT (referee_id) DO NOTHING`,
        [referredBy, userId, affiliateCode.trim().toUpperCase()],
      );
    }

    await client.query('COMMIT');

    // 9. Issue tokens
    const accessToken  = signAccessToken(userId, email.toLowerCase());
    const refreshToken = await issueRefreshToken(userId, ip);

    logger.info('New user registered', { userId, email });
    return { userId, email: email.toLowerCase(), accessToken, refreshToken };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ── Login ──────────────────────────────────────────────────────────────────────

async function login(email, password, ip) {
  const { rows } = await db.query(
    `SELECT id, email, password_hash, full_name, deriv_account, referral_code
     FROM users WHERE email = $1 AND is_active = TRUE`,
    [email.toLowerCase()],
  );

  const user = rows[0];
  if (!user || !(await bcrypt.compare(password, user.password_hash))) {
    const err = new Error('Invalid email or password.');
    err.type = 'UNAUTHORIZED';
    throw err;
  }

  const accessToken  = signAccessToken(user.id, user.email);
  const refreshToken = await issueRefreshToken(user.id, ip);

  return {
    accessToken,
    refreshToken,
    user: {
      id:           user.id,
      email:        user.email,
      fullName:     user.full_name,
      derivAccount: user.deriv_account,
      referralCode: user.referral_code,
    },
  };
}

// ── Refresh tokens ─────────────────────────────────────────────────────────────

async function refresh(rawToken, ip) {
  const hash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const { rows } = await db.query(
    `SELECT id, user_id, expires_at, revoked_at
     FROM refresh_tokens WHERE token_hash = $1`,
    [hash],
  );

  const rt = rows[0];
  if (!rt || rt.revoked_at || new Date(rt.expires_at) < new Date()) {
    const err = new Error('Refresh token invalid or expired.');
    err.type = 'UNAUTHORIZED';
    throw err;
  }

  // Revoke old token (rotation)
  await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1', [rt.id]);

  const userResult = await db.query('SELECT id, email FROM users WHERE id = $1', [rt.user_id]);
  const user = userResult.rows[0];
  if (!user) {
    const err = new Error('User not found.');
    err.type = 'UNAUTHORIZED';
    throw err;
  }

  const accessToken  = signAccessToken(user.id, user.email);
  const refreshToken = await issueRefreshToken(user.id, ip);
  return { accessToken, refreshToken };
}

// ── Logout ────────────────────────────────────────────────────────────────────

async function logout(rawToken) {
  if (!rawToken) return;
  const hash = crypto.createHash('sha256').update(rawToken).digest('hex');
  await db.query(
    'UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL',
    [hash],
  );
}

// ── Forgot/Reset password ─────────────────────────────────────────────────────

async function forgotPassword(email) {
  // Just confirm email exists. The OTP is sent via /otp/send endpoint separately.
  const { rows } = await db.query('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
  // We return success regardless to avoid user enumeration
  return { found: rows.length > 0 };
}

async function resetPassword(verificationToken, newPassword) {
  const verified = parseVerificationToken(verificationToken);
  if (!verified || verified.purpose !== 'password_reset') {
    const err = new Error('Invalid or expired verification token.');
    err.type = 'VALIDATION';
    throw err;
  }

  const hash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
  const { rowCount } = await db.query(
    `UPDATE users SET password_hash = $1, updated_at = NOW()
     WHERE email = $2`,
    [hash, verified.destination],
  );

  if (rowCount === 0) {
    const err = new Error('Account not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }
}

module.exports = {
  register, login, refresh, logout, forgotPassword, resetPassword,
  // Shared helpers used by biometric.service.js
  signAccessToken, issueRefreshToken,
};
