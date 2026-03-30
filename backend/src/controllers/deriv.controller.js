'use strict';

const derivService = require('../services/deriv.service');

/**
 * POST /deriv/connect
 * Body: { derivToken, derivAccount }
 *
 * - Open endpoint (no JWT required) — used during signup to verify the token
 *   and return the Deriv profile so the app can pre-fill the signup form.
 * - If the request carries a valid JWT (req.user is set by optional auth),
 *   the token is also persisted in the database.
 */
async function connectAccount(req, res, next) {
  try {
    const { derivToken, derivAccount } = req.body;
    const userId = req.user?.id ?? null;  // set by optional authenticate middleware
    const result = await derivService.connectAccount(derivToken, derivAccount, userId);
    res.json(result);
  } catch (err) { next(err); }
}

async function getBalance(req, res, next) {
  try {
    const balances = await derivService.getBalances(req.user.id);
    res.json(balances);
  } catch (err) { next(err); }
}

module.exports = { connectAccount, getBalance };
