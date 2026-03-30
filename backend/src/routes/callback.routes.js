'use strict';

// M-Pesa callbacks — no JWT (Safaricom-initiated, no auth header)
// We respond 200 immediately on every callback (Safaricom retries if we don't)

const router = require('express').Router();
const ctrl   = require('../controllers/callback.controller');

router.post('/mpesa/stk',         ctrl.handleSTKCallback);
router.post('/mpesa/b2c/result',  ctrl.handleB2CResult);
router.post('/mpesa/b2c/timeout', ctrl.handleB2CTimeout);

module.exports = router;
