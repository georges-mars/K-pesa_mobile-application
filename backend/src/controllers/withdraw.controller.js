'use strict';

const db     = require('../config/database');
const mpesa  = require('../services/mpesa.service');
const forex  = require('../services/forex.service');
const deriv  = require('../services/deriv.service');
const { normalizeKenyanPhone } = require('../services/phone.service');
const logger = require('../config/logger');

async function initiate(req, res, next) {
  try {
    const { amountUsd, sourceType, mpesaPhone } = req.body;
    const userId = req.user.id;
    const normalizedPhone = normalizeKenyanPhone(mpesaPhone);

    // Check live balance (skip balance check for binance — not integrated yet)
    if (sourceType !== 'binance') {
      const balances = await deriv.getBalances(userId);
      const available = sourceType === 'mt5'
        ? balances.mt5?.balance
        : balances.deriv?.balance;

      if (available === null || available === undefined) {
        const e = new Error('Could not fetch your account balance. Please try again.');
        e.type = 'SERVICE_UNAVAILABLE';
        throw e;
      }
      if (amountUsd > available) {
        const e = new Error(`Insufficient balance. Available: ${available} USD`);
        e.type = 'VALIDATION';
        throw e;
      }
    }

    const { kes: amountKes, rate: exchangeRate } = await forex.usdToKes(amountUsd);

    const { rows } = await db.query(
      `INSERT INTO transactions
         (user_id, type, status, amount_kes, amount_usd, exchange_rate, mpesa_phone, destination_type)
       VALUES ($1,'withdrawal','pending',$2,$3,$4,$5,$6)
       RETURNING id`,
      [userId, amountKes, amountUsd, exchangeRate, normalizedPhone, sourceType],
    );
    const transactionId = rows[0].id;

    let conversationId;
    try {
      const result = await mpesa.b2cPay(normalizedPhone, amountKes, transactionId);
      conversationId = result.conversationId;
    } catch (err) {
      await db.query(`UPDATE transactions SET status='failed', failure_reason=$1 WHERE id=$2`, [err.message, transactionId]);
      const e = new Error('M-Pesa service temporarily unavailable. Please try again.');
      e.type = 'SERVICE_UNAVAILABLE';
      throw e;
    }

    await db.query(
      `UPDATE transactions
       SET b2c_conversation_id=$1, b2c_originator_id=$2, status='processing', updated_at=NOW()
       WHERE id=$3`,
      [conversationId, transactionId, transactionId],
    );

    logger.info('Withdrawal initiated', { userId, transactionId, amountUsd, amountKes });
    res.json({
      transactionId,
      estimatedKes: amountKes,
      exchangeRate,
      message: 'Withdrawal initiated. Funds typically arrive in 1-3 minutes.',
    });
  } catch (err) { next(err); }
}

async function getStatus(req, res, next) {
  try {
    const { rows } = await db.query(
      `SELECT id, status, amount_kes, amount_usd, b2c_transaction_id, failure_reason
       FROM transactions WHERE id=$1 AND user_id=$2 AND type='withdrawal'`,
      [req.params.transactionId, req.user.id],
    );
    if (!rows[0]) return res.status(404).json({ error: 'Transaction not found.' });
    res.json(rows[0]);
  } catch (err) { next(err); }
}

module.exports = { initiate, getStatus };
