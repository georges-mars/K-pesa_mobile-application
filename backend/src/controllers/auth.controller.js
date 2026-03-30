'use strict';

const authService = require('../services/auth.service');
const otpService  = require('../services/otp.service');
const logger      = require('../config/logger');

const clientIp = (req) => req.headers['x-forwarded-for']?.split(',')[0] || req.socket.remoteAddress;

/**
 * POST /api/v1/auth/register
 */
async function register(req, res, next) {
  try {
    const result = await authService.register(req.body, clientIp(req));
    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/auth/login
 */
async function login(req, res, next) {
  try {
    const { email, password } = req.body;
    const result = await authService.login(email, password, clientIp(req));
    res.json(result);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/auth/refresh
 */
async function refresh(req, res, next) {
  try {
    const { refreshToken } = req.body;
    const result = await authService.refresh(refreshToken, clientIp(req));
    res.json(result);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/auth/logout
 */
async function logout(req, res, next) {
  try {
    const { refreshToken } = req.body || {};
    await authService.logout(refreshToken);
    res.json({ message: 'Logged out successfully.' });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/auth/forgot-password
 * Body: { email }
 * Triggers an OTP send via the OTP service (type=email, purpose=password_reset).
 */
async function forgotPassword(req, res, next) {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email is required.' });

    await authService.forgotPassword(email);
    // Send OTP regardless of whether email exists (to avoid user enumeration)
    await otpService.sendOtp('email', email, 'password_reset').catch(() => {});

    res.json({ message: 'If an account with that email exists, a reset code has been sent.' });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/auth/reset-password
 * Body: { verificationToken, newPassword }
 */
async function resetPassword(req, res, next) {
  try {
    const { verificationToken, newPassword } = req.body;
    await authService.resetPassword(verificationToken, newPassword);
    res.json({ message: 'Password reset successfully. Please log in.' });
  } catch (err) {
    next(err);
  }
}

module.exports = { register, login, refresh, logout, forgotPassword, resetPassword };
