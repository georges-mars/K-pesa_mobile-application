'use strict';

const router = require('express').Router();
const { otpSendLimiter, otpVerifyLimiter } = require('../middleware/rateLimiter');
const validate = require('../middleware/validate');
const ctrl     = require('../controllers/otp.controller');
const Joi      = require('joi');

const sendSchema = Joi.object({
  destination: Joi.string().required(),
  type:        Joi.string().valid('sms', 'email').required(),
  purpose:     Joi.string().valid('signup', 'login', 'password_reset', 'withdrawal').required(),
});

const verifySchema = Joi.object({
  destination: Joi.string().required(),
  otp:         Joi.string().length(6).pattern(/^\d+$/).required(),
  purpose:     Joi.string().valid('signup', 'login', 'password_reset', 'withdrawal').required(),
});

router.post('/send',   otpSendLimiter,   validate(sendSchema),   ctrl.send);
router.post('/verify', otpVerifyLimiter, validate(verifySchema), ctrl.verify);

module.exports = router;
