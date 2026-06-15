'use strict';

const router = require('express').Router();
const Joi    = require('joi');
const validate = require('../middleware/validate');
const ctrl     = require('../controllers/admin.controller');
const authenticate = require('../middleware/authenticate');

const adminOnly = (req, res, next) => {
  if (req.user && req.user.email === (process.env.ADMIN_EMAIL || 'admin@k-pesa.tech')) {
    return next();
  }
  return res.status(403).json({ error: 'Access denied. Admins only.' });
};

const initiateChangeSchema = Joi.object({
  proposed_code: Joi.string().min(3).max(50).required(),
  email: Joi.string().email().allow(null, ''),
  phone: Joi.string().min(7).max(20).allow(null, ''),
  reward_type: Joi.string().valid('flat_amount_limit', 'flat_date_limit', 'revenue_share_limit').required(),
  percentage: Joi.number().min(0).max(100).allow(null, ''),
  expiry_amount: Joi.number().precision(2).min(0).allow(null, ''),
  expiry_date: Joi.date().iso().allow(null, ''),
  fixed_amount: Joi.number().precision(2).min(0).allow(null, ''),
}).or('email', 'phone');

const confirmChangeSchema = Joi.object({
  otpRequestId: Joi.string().uuid().required(),
  otp: Joi.string().length(6).required(),
});

const updateConfigSchema = Joi.object({
  referral_type: Joi.string().valid('flat_amount_limit', 'flat_date_limit', 'revenue_share_limit').required(),
  referral_value: Joi.number().precision(2).min(0).required(),
});

// New Referral System Overhaul Schemas
const createReferralSchema = Joi.object({
  userId: Joi.string().uuid().required(),
  customCode: Joi.string().min(3).max(50).required(),
  divisionType: Joi.string().valid('flat_with_expiry_amount', 'flat_with_expiry_date', 'fixed_split').required(),
  rewardValue: Joi.number().precision(2).min(0).allow(null, ''),
  splitPercentageUser: Joi.number().min(0).max(100).allow(null, ''),
  splitPercentageus: Joi.number().min(0).max(100).allow(null, ''),
  expiryAmount: Joi.number().precision(2).min(0).allow(null, ''),
  expiryDate: Joi.date().iso().allow(null, ''),
  fixedSplitCap: Joi.number().precision(2).min(0).allow(null, ''),
  deliveryMethod: Joi.string().valid('email', 'sms').required(),
  destination: Joi.string().required(),
});

const verifyOtpSchema = Joi.object({
  requestId: Joi.string().uuid().required(),
  otp: Joi.string().length(6).required(),
});

// Existing Admin routes
router.get('/referral/codes', ctrl.getReferralCodes);
router.post('/referral/initiate-change', validate(initiateChangeSchema), ctrl.initiateChange);
router.post('/referral/confirm-change', validate(confirmChangeSchema), ctrl.confirmChange);
router.delete('/referral-codes/:id', ctrl.deleteReferralCode);

router.get('/config', ctrl.getConfig);
router.post('/config', validate(updateConfigSchema), ctrl.updateConfig);

// New Referral Overhaul admin endpoints
router.post('/referral/create', validate(createReferralSchema), ctrl.createReferral);
router.post('/referral/verify-otp', validate(verifyOtpSchema), ctrl.verifyReferralOtp);
router.get('/referral/users', ctrl.getReferralUsers);

module.exports = router;
