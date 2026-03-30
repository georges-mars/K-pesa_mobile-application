'use strict';

const router       = require('express').Router();
const { authLimiter } = require('../middleware/rateLimiter');
const validate     = require('../middleware/validate');
const authenticate = require('../middleware/authenticate');
const ctrl         = require('../controllers/biometric.controller');
const Joi          = require('joi');

const enrollSchema = Joi.object({
  deviceId:   Joi.string().min(1).max(255).required(),
  deviceName: Joi.string().max(255).allow('', null),
});

const loginSchema = Joi.object({
  deviceId: Joi.string().min(1).max(255).required(),
});

const removeSchema = Joi.object({
  deviceId: Joi.string().min(1).max(255).required(),
});

router.post('/enroll',  authenticate, validate(enrollSchema),  ctrl.enroll);
router.post('/login',   authLimiter,  validate(loginSchema),   ctrl.loginBiometric);
router.delete('/remove', authenticate, validate(removeSchema), ctrl.remove);

module.exports = router;
