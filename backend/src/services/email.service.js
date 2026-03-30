'use strict';

const nodemailer = require('nodemailer');
const logger     = require('../config/logger');

// Reuse a single transporter across requests
const transporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST,
  port:   parseInt(process.env.SMTP_PORT || '587'),
  secure: parseInt(process.env.SMTP_PORT || '587') === 465,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

/**
 * Send an OTP email.
 * @param {string} toEmail
 * @param {string} otp      - 6-digit code
 * @returns {Promise<boolean>}
 */
async function sendOtpEmail(toEmail, otp) {
  const subject = 'Your K-PESA verification code';
  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:auto">
      <h2 style="color:#37c215">K-PESA Verification</h2>
      <p>Your one-time code is:</p>
      <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#222;padding:16px 0">${otp}</div>
      <p style="color:#666;font-size:13px">Valid for 10 minutes. Do not share this code.</p>
    </div>
  `;

  try {
    await transporter.sendMail({
      from:    `"K-PESA" <${process.env.EMAIL_FROM}>`,
      to:      toEmail,
      subject,
      html,
    });
    logger.info('OTP email sent', { to: toEmail });
    return true;
  } catch (err) {
    logger.error('Email send error', { to: toEmail, error: err.message });
    return false;
  }
}

module.exports = { sendOtpEmail };
