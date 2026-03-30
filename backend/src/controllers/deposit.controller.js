'use strict';

const db     = require('../config/database');
const mpesa  = require('../services/mpesa.service');
const forex  = require('../services/forex.service');
const logger = require('../config/logger');

async function initiate(req, res, next) {
  try {
    const { amountKes, destinationType, mpesaPhone } = req.body;
    const userId = req.user.id;

    const { usd: amountUsd, rate: exchangeRate } = await forex.kesToUsd(amountKes);

    const { rows } = await db.query(
      `INSERT INTO transactions
         (user_id, type, status, amount_kes, amount_usd, exchange_rate, mpesa_phone, destination_type)
       VALUES ($1,'deposit','pending',$2,$3,$4,$5,$6)
       RETURNING id`,
      [userId, amountKes, amountUsd, exchangeRate, mpesaPhone, destinationType],
    );
    const transactionId = rows[0].id;

    const reference = `KPESA-${transactionId.slice(0, 8).toUpperCase()}`;
    let checkoutRequestId;
    try {
      const result = await mpesa.stkPush(mpesaPhone, amountKes, reference);
      checkoutRequestId = result.checkoutRequestId;
    } catch (err) {
      await db.query(`UPDATE transactions SET status='failed', failure_reason=$1 WHERE id=$2`, [err.message, transactionId]);
      const e = new Error('M-Pesa service temporarily unavailable. Please try again.');
      e.type = 'SERVICE_UNAVAILABLE';
      throw e;
    }

    await db.query(
      `UPDATE transactions SET mpesa_checkout_request_id=$1, status='processing', updated_at=NOW() WHERE id=$2`,
      [checkoutRequestId, transactionId],
    );

    logger.info('Deposit initiated', { userId, transactionId, amountKes });
    res.json({
      transactionId,
      checkoutRequestId,
      message: `A payment prompt has been sent to ${mpesaPhone}. Enter your M-Pesa PIN to complete.`,
    });
  } catch (err) { next(err); }
}

async function getStatus(req, res, next) {
  try {
    const { rows } = await db.query(
      `SELECT id, status, amount_kes, amount_usd, mpesa_transaction_id, failure_reason
       FROM transactions WHERE id=$1 AND user_id=$2 AND type='deposit'`,
      [req.params.transactionId, req.user.id],
    );
    if (!rows[0]) return res.status(404).json({ error: 'Transaction not found.' });
    res.json(rows[0]);
  } catch (err) { next(err); }
}

module.exports = { initiate, getStatus };
