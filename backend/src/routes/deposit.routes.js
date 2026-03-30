'use strict';

const router       = require('express').Router();
const authenticate = require('../middleware/authenticate');
const validate     = require('../middleware/validate');
const ctrl         = require('../controllers/deposit.controller');
const Joi          = require('joi');

const initiateSchema = Joi.object({
  amountKes:       Joi.number().min(665).max(250000).required(),
  destinationType: Joi.string().valid('deriv', 'mt5', 'binance').required(),
  mpesaPhone:      Joi.string().pattern(/^\+2547\d{8}$/).required()
    .messages({ 'string.pattern.base': 'Phone must be a valid Kenyan M-Pesa number in E.164 format (+2547XXXXXXXX)' }),
});

router.use(authenticate);

router.post('/initiate', validate(initiateSchema), ctrl.initiate);
router.get('/:transactionId/status',              ctrl.getStatus);

module.exports = router;
