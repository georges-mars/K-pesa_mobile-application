'use strict';

const router       = require('express').Router();
const authenticate = require('../middleware/authenticate');
const validate     = require('../middleware/validate');
const ctrl         = require('../controllers/user.controller');
const Joi          = require('joi');

const updateProfileSchema = Joi.object({
  fullName:    Joi.string().min(1).max(255),
  displayName: Joi.string().min(1).max(100),
});

const addPaymentMethodSchema = Joi.object({
  type:          Joi.string().valid('mpesa', 'airtel', 'bank').required(),
  phoneNumber:   Joi.string().allow(null, ''),
  bankName:      Joi.string().allow(null, ''),
  accountName:   Joi.string().allow(null, ''),
  accountNumber: Joi.string().allow(null, ''),
  isDefault:     Joi.boolean().default(false),
});

router.use(authenticate);

router.get('/profile',                          ctrl.getProfile);
router.patch('/profile', validate(updateProfileSchema), ctrl.updateProfile);
router.get('/payment-methods',                  ctrl.listPaymentMethods);
const changePasswordVerifySchema = Joi.object({
  password: Joi.string().required(),
});

const changePasswordConfirmSchema = Joi.object({
  verificationToken: Joi.string().required(),
  newPassword:       Joi.string().min(8).required(),
});

router.post('/payment-methods', validate(addPaymentMethodSchema), ctrl.addPaymentMethod);
router.delete('/payment-methods/:id',           ctrl.deletePaymentMethod);
router.patch('/payment-methods/:id/set-default', ctrl.setDefaultPaymentMethod);
router.get('/balances',                         ctrl.getBalances);
router.get('/transactions',                     ctrl.listTransactions);
router.get('/earnings',                         ctrl.getEarnings);
router.get('/profile/referral',                ctrl.getReferralProfile);

router.post('/change-password/verify', validate(changePasswordVerifySchema), ctrl.verifyPassword);
router.post('/change-password/confirm', validate(changePasswordConfirmSchema), ctrl.changePassword);

module.exports = router;
