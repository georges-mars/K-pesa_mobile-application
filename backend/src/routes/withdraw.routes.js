'use strict';

const router       = require('express').Router();
const authenticate = require('../middleware/authenticate');
const validate     = require('../middleware/validate');
const ctrl         = require('../controllers/withdraw.controller');
const Joi          = require('joi');

const initiateSchema = Joi.object({
  amountUsd:   Joi.number().min(5).max(10000).required(),
  sourceType:  Joi.string().valid('deriv', 'mt5', 'binance').required(),
  mpesaPhone:  Joi.string().pattern(/^\+2547\d{8}$/).required()
    .messages({ 'string.pattern.base': 'Phone must be a valid Kenyan M-Pesa number in E.164 format (+2547XXXXXXXX)' }),
});

router.use(authenticate);

router.post('/initiate', validate(initiateSchema), ctrl.initiate);
router.get('/:transactionId/status',              ctrl.getStatus);

module.exports = router;
