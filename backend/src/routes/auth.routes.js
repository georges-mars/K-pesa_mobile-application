'use strict';

const router = require('express').Router();
const { authLimiter }   = require('../middleware/rateLimiter');
const validate           = require('../middleware/validate');
const authenticate       = require('../middleware/authenticate');
const ctrl               = require('../controllers/auth.controller');
const Joi                = require('joi');

const registerSchema = Joi.object({
  email:             Joi.string().email().required(),
  password:          Joi.string().min(8).required(),
  verificationToken: Joi.string().required(),
  fullName:          Joi.string().min(1).max(255).required(),
  derivEmail:        Joi.string().email().allow('', null),
  derivName:         Joi.string().allow('', null),
  derivAccount:      Joi.string().allow('', null),
  binanceId:         Joi.string().allow('', null),
  mpesaPhone:        Joi.string().allow('', null),
  airtelPhone:       Joi.string().allow('', null),
  bankName:          Joi.string().allow('', null),
  bankAccountName:   Joi.string().allow('', null),
  bankAccountNumber: Joi.string().allow('', null),
  affiliateCode:     Joi.string().allow('', null),
});

const loginSchema = Joi.object({
  email:    Joi.string().email().required(),
  password: Joi.string().required(),
});

const refreshSchema = Joi.object({
  refreshToken: Joi.string().required(),
});

const resetPasswordSchema = Joi.object({
  verificationToken: Joi.string().required(),
  newPassword:       Joi.string().min(8).required(),
});

const forgotPasswordSchema = Joi.object({
  email: Joi.string().email().required(),
});

router.post('/register',        authLimiter, validate(registerSchema),        ctrl.register);
router.post('/login',           authLimiter, validate(loginSchema),           ctrl.login);
router.post('/refresh',         authLimiter, validate(refreshSchema),         ctrl.refresh);
router.post('/logout',          authenticate,                                  ctrl.logout);
router.post('/forgot-password', authLimiter, validate(forgotPasswordSchema),  ctrl.forgotPassword);
router.post('/reset-password',  authLimiter, validate(resetPasswordSchema),   ctrl.resetPassword);

module.exports = router;
