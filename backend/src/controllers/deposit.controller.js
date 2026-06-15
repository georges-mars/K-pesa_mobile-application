'use strict';

const db     = require('../config/database');
const mpesa  = require('../services/mpesa.service');
const forex  = require('../services/forex.service');
const { normalizeKenyanPhone } = require('../services/phone.service');
const logger = require('../config/logger');
const userService = require('../services/user.service');

async function initiate(req, res, next) {
  try {
    const { amountKes, destinationType, mpesaPhone } = req.body;
    const userId = req.user.id;
    const normalizedPhone = normalizeKenyanPhone(mpesaPhone);

    const { usd: amountUsd, rate: exchangeRate } = await forex.kesToUsd(amountKes);
    const minDepositUsd = Number(process.env.MIN_DEPOSIT_USD || 5);
    if (amountUsd < minDepositUsd) {
      const e = new Error(`Minimum deposit amount is ${minDepositUsd} USD.`);
      e.type = 'VALIDATION';
      throw e;
    }

    const { rows } = await db.query(
      `INSERT INTO transactions
         (user_id, type, status, amount_kes, amount_usd, exchange_rate, mpesa_phone, destination_type)
       VALUES ($1,'deposit','pending',$2,$3,$4,$5,$6)
       RETURNING id`,
      [userId, amountKes, amountUsd, exchangeRate, normalizedPhone, destinationType],
    );
    const transactionId = rows[0].id;

    // Fetch linked destination identifiers and enforce destination-specific routing
    const { rows: userRows } = await db.query(
      `SELECT deriv_account, deriv_email, deriv_name, binance_id FROM users WHERE id = $1`,
      [userId],
    );
    const user = userRows[0];
    let reference;
    if (destinationType === 'binance') {
      if (!user?.binance_id) {
        const e = new Error('Binance is not linked. Link Binance first, then try again.');
        e.type = 'VALIDATION';
        throw e;
      }
      reference = user.binance_id;
    } else {
      // Deriv + MT5 both depend on linked Deriv account
      const derivReference = user?.deriv_account || user?.deriv_email || user?.deriv_name;
      if (!derivReference) {
        const e = new Error('Deriv is not linked. Link Deriv first, then try again.');
        e.type = 'VALIDATION';
        throw e;
      }
      reference = derivReference;
    }

    let checkoutRequestId;
    try {
      const result = await mpesa.stkPush(normalizedPhone, amountKes, reference);
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

    logger.info('Deposit initiated', { userId, transactionId, amountKes, accountReference: reference });
    res.json({
      transactionId,
      checkoutRequestId,
      message: `A payment prompt has been sent to ${normalizedPhone}. Enter your M-Pesa PIN to complete.`,
    });
  } catch (err) { next(err); }
}

async function getStatus(req, res, next) {
  try {
    const { rows } = await db.query(
      `SELECT id, status, amount_kes, amount_usd, mpesa_transaction_id, failure_reason, mpesa_checkout_request_id, created_at
       FROM transactions WHERE id=$1 AND user_id=$2 AND type='deposit'`,
      [req.params.transactionId, req.user.id],
    );
    if (!rows[0]) return res.status(404).json({ error: 'Transaction not found.' });
    
    let transaction = rows[0];
    if (['pending', 'processing'].includes(transaction.status)) {
      transaction = await userService.syncTransactionStatus(transaction);
    }
    
    res.json({
      id: transaction.id,
      status: transaction.status,
      amount_kes: transaction.amount_kes,
      amount_usd: transaction.amount_usd,
      mpesa_transaction_id: transaction.mpesa_transaction_id,
      failure_reason: transaction.failure_reason,
    });
  } catch (err) { next(err); }
}

module.exports = { initiate, getStatus };
