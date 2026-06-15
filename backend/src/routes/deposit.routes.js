'use strict';

const router       = require('express').Router();
const authenticate = require('../middleware/authenticate');
const validate     = require('../middleware/validate');
const ctrl         = require('../controllers/deposit.controller');
const Joi          = require('joi');
const { KENYAN_MOBILE_PATTERN } = require('../services/phone.service');

const initiateSchema = Joi.object({
  amountKes:       Joi.number().min(1).max(250000).required(),
  destinationType: Joi.string().valid('deriv', 'mt5', 'binance').required(),
  mpesaPhone:      Joi.string().pattern(KENYAN_MOBILE_PATTERN).required().messages({
    'string.pattern.base':
      'Phone must be a valid Kenyan mobile number (07XXXXXXXX, 01XXXXXXXX, or +254XXXXXXXXX).',
  }),
});

router.use(authenticate);

router.post('/initiate', validate(initiateSchema), ctrl.initiate);
router.get('/:transactionId/status',              ctrl.getStatus);

module.exports = router;
