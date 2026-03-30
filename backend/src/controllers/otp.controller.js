'use strict';

const otpService = require('../services/otp.service');
const logger     = require('../config/logger');

/**
 * POST /api/v1/otp/send
 * Body: { destination, type, purpose }
 */
async function send(req, res, next) {
  try {
    const { destination, type, purpose } = req.body;
    const result = await otpService.sendOtp(type, destination, purpose);

    if (!result.sent) {
      return res.status(503).json({
        error: type === 'sms'
          ? 'Could not send SMS. Check the phone number and try again.'
          : 'Could not send email. Check the address and try again.',
      });
    }

    res.json({
      message:   'OTP sent.',
      channel:   result.channel,
      expiresIn: result.expiresIn,
    });
  } catch (err) {
    logger.error('OTP send error', { error: err.message });
    next(err);
  }
}

/**
 * POST /api/v1/otp/verify
 * Body: { destination, otp, purpose }
 */
async function verify(req, res, next) {
  try {
    const { destination, otp, purpose } = req.body;
    const result = await otpService.verifyOtp(destination, otp, purpose);

    if (!result.valid) {
      const status = result.attemptsRemaining === 0 ? 423 : 400;
      return res.status(status).json({
        valid:             false,
        error:             result.error,
        attemptsRemaining: result.attemptsRemaining,
      });
    }

    res.json({
      valid:             true,
      verificationToken: result.verificationToken,
    });
  } catch (err) {
    logger.error('OTP verify error', { error: err.message });
    next(err);
  }
}

module.exports = { send, verify };
