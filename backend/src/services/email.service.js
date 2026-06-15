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
    pass: process.env.SMTP_PASS ? process.env.SMTP_PASS.replace(/\s/g, '') : '',
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
      from:    '"K-PESA Security" <otp@k-pesa.tech>',
      to:      toEmail,
      subject,
      html,
    });
    logger.info('OTP email sent', { to: toEmail });
    return true;
  } catch (err) {
    logger.error('Email send error. [DEV FALLBACK] OTP was: ' + otp, { to: toEmail, error: err.message });
    return false;
  }
}

/**
 * Send a custom referral code invitation email.
 * @param {string} toEmail
 * @param {string} referralCode
 * @returns {Promise<boolean>}
 */
async function sendReferralEmail(toEmail, referralCode) {
  const subject = 'Your K-PESA Invitation & Custom Referral Code';
  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:auto;border:1px solid #eee;border-radius:12px;padding:24px;background-color:#fcfcfc">
      <h2 style="color:#37c215;margin-top:0">Welcome to K-PESA</h2>
      <p>Hello,</p>
      <p>You have been invited to join K-PESA! Use the custom referral code below during your signup to unlock exclusive benefits.</p>
      <div style="font-size:28px;font-weight:bold;letter-spacing:2px;color:#37c215;background-color:#f1faf0;border:1px dashed #37c215;border-radius:8px;padding:16px;text-align:center;margin:24px 0">
        ${referralCode}
      </div>
      <p style="color:#555;font-size:14px">Simply enter this code in the **Referral Code** field when completing your registration on the K-PESA app.</p>
      <hr style="border:0;border-top:1px solid #eee;margin:24px 0" />
      <p style="color:#999;font-size:12px;text-align:center">This is an automated invitation from K-PESA.</p>
    </div>
  `;

  try {
    await transporter.sendMail({
      from:    '"K-PESA" <no-reply@k-pesa.tech>',
      to:      toEmail,
      subject,
      html,
    });
    logger.info('Referral email sent', { to: toEmail, code: referralCode });
    return true;
  } catch (err) {
    logger.error('Referral email send error. [DEV FALLBACK] Referral code was: ' + referralCode, { to: toEmail, error: err.message });
    return false;
  }
}

/**
 * Send an OTP email to confirm referral code config change.
 * @param {string} toEmail
 * @param {string} code
 * @param {string} terms
 * @param {string} otp
 * @returns {Promise<boolean>}
 */
async function sendReferralChangeOtpEmail(toEmail, code, terms, otp) {
  const subject = 'Confirm K-PESA Referral Code Change';
  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:auto;border:1px solid #eee;border-radius:12px;padding:24px;background-color:#fcfcfc">
      <h2 style="color:#37c215;margin-top:0">Referral Code Change Request</h2>
      <p>Hello,</p>
      <p>A request has been initiated to change or configure your K-PESA custom referral agreement details.</p>
      <div style="background-color:#f8f9fa;padding:16px;border-radius:8px;margin:16px 0;font-size:14px;color:#333;border:1px solid #dee2e6;">
        <strong>New Referral Code:</strong> ${code}<br/>
        <strong>Agreement Terms:</strong> ${terms}
      </div>
      <p>Your one-time confirmation code (OTP) is:</p>
      <div style="font-size:32px;font-weight:bold;letter-spacing:6px;color:#37c215;text-align:center;padding:16px 0">
        ${otp}
      </div>
      <p style="color:#666;font-size:13px;text-align:center">This code is valid for 10 minutes. If you did not request this, please contact support.</p>
    </div>
  `;

  try {
    await transporter.sendMail({
      from:    '"K-PESA Security" <otp@k-pesa.tech>',
      to:      toEmail,
      subject,
      html,
    });
    logger.info('Referral change OTP email sent', { to: toEmail });
    return true;
  } catch (err) {
    logger.error('Referral change OTP email send error. [DEV FALLBACK] OTP was: ' + otp, { to: toEmail, error: err.message });
    return false;
  }
}

/**
 * Send an OTP email to confirm referral code config change (new schema).
 */
async function sendReferralChangeOtp(toEmail, newCode, terms, otp, expiresAt) {
  const subject = 'Referral Code Change Request';
  const expiryStr = new Date(expiresAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  const html = `
    <div style="font-family:sans-serif;max-width:480px;margin:auto;border:1px solid #eee;border-radius:12px;padding:24px;background-color:#fcfcfc">
      <h2 style="color:#37c215;margin-top:0">Referral Code Change Request</h2>
      <p>Hello,</p>
      <p>Your referral code is being changed to <strong>${newCode}</strong>.</p>
      <div style="background-color:#f8f9fa;padding:16px;border-radius:8px;margin:16px 0;font-size:14px;color:#333;border:1px solid #dee2e6;">
        <strong>Agreement Terms:</strong> ${terms}
      </div>
      <p>Your one-time confirmation code (OTP) is:</p>
      <div style="font-size:32px;font-weight:bold;letter-spacing:6px;color:#37c215;text-align:center;padding:16px 0">
        ${otp}
      </div>
      <p style="color:#666;font-size:13px;text-align:center">This code is valid until ${expiryStr}. If you did not request this, please contact support.</p>
    </div>
  `;

  try {
    await transporter.sendMail({
      from:    '"K-PESA Security" <otp@k-pesa.tech>',
      to:      toEmail,
      subject,
      html,
    });
    logger.info('New Referral change OTP email sent', { to: toEmail });
    return true;
  } catch (err) {
    logger.error('New Referral change OTP email send error. [DEV FALLBACK] OTP was: ' + otp, { to: toEmail, error: err.message });
    return false;
  }
}

module.exports = { sendOtpEmail, sendReferralEmail, sendReferralChangeOtpEmail, sendReferralChangeOtp };
