'use strict';

const router       = require('express').Router();
const authenticate = require('../middleware/authenticate');
const validate     = require('../middleware/validate');
const ctrl         = require('../controllers/deriv.controller');
const Joi          = require('joi');

const connectSchema = Joi.object({
  derivToken:   Joi.string().required(),
  derivAccount: Joi.string().allow('', null).optional(),
});

// Optional auth: if a valid JWT is present, req.user is set and the token
// gets stored in the DB. Without a JWT it still works (signup pre-fill flow).
router.post('/connect',  validate(connectSchema), authenticate.optional, ctrl.connectAccount);
router.get('/balance',   authenticate,            ctrl.getBalance);

module.exports = router;
