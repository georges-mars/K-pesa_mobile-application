'use strict';

const db     = require('../config/database');
const logger = require('../config/logger');
const { signAccessToken, issueRefreshToken } = require('./auth.service');

// ── Enroll Device ─────────────────────────────────────────────────────────────

/**
 * Associate a device with a user for biometric login.
 * Upserts — if the device was previously registered (even by another user),
 * it gets reassigned to the new user.
 */
async function enrollDevice(userId, deviceId, deviceName) {
  const result = await db.query(
    `INSERT INTO device_biometrics (user_id, device_id, device_name)
     VALUES ($1, $2, $3)
     ON CONFLICT (device_id)
     DO UPDATE SET user_id = $1, device_name = $3, is_active = TRUE, updated_at = NOW()
     RETURNING id`,
    [userId, deviceId, deviceName || null],
  );
  logger.info('Device enrolled for biometric login', { userId, deviceId });
  return result.rows[0];
}

// ── Biometric Login ───────────────────────────────────────────────────────────

/**
 * Log in by device ID. Returns tokens + user profile, same shape as auth.login.
 */
async function loginByDevice(deviceId, ip) {
  const { rows } = await db.query(
    `SELECT u.id, u.email, u.full_name, u.deriv_account, u.referral_code
     FROM device_biometrics d
     JOIN users u ON u.id = d.user_id
     WHERE d.device_id = $1 AND d.is_active = TRUE AND u.is_active = TRUE`,
    [deviceId],
  );

  if (rows.length === 0) {
    const err = new Error('Device not enrolled or user inactive.');
    err.type = 'UNAUTHORIZED';
    throw err;
  }

  const user = rows[0];
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

// ── Remove Device ─────────────────────────────────────────────────────────────

/**
 * Soft-delete: mark a device as inactive so it can no longer be used for login.
 */
async function removeDevice(userId, deviceId) {
  const { rowCount } = await db.query(
    `UPDATE device_biometrics SET is_active = FALSE, updated_at = NOW()
     WHERE user_id = $1 AND device_id = $2 AND is_active = TRUE`,
    [userId, deviceId],
  );
  if (rowCount === 0) {
    const err = new Error('Device not found or already removed.');
    err.type = 'NOT_FOUND';
    throw err;
  }
  logger.info('Device removed from biometric login', { userId, deviceId });
}

// ── List Devices ──────────────────────────────────────────────────────────────

async function getDevices(userId) {
  const { rows } = await db.query(
    `SELECT id, device_id, device_name, created_at
     FROM device_biometrics
     WHERE user_id = $1 AND is_active = TRUE
     ORDER BY created_at DESC`,
    [userId],
  );
  return rows;
}

module.exports = { enrollDevice, loginByDevice, removeDevice, getDevices };
