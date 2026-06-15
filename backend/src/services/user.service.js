'use strict';

const db     = require('../config/database');
const logger = require('../config/logger');
const cryptoService = require('./crypto.service');
const mpesaService = require('./mpesa.service');
const bcrypt = require('bcryptjs');
const otpService = require('./otp.service');

async function getProfile(userId) {
  const { rows } = await db.query(
    `SELECT id, email, full_name, display_name, deriv_email, deriv_name, deriv_account,
            binance_id, referral_code, referral_earnings, is_verified, created_at, pii_key_version
     FROM users WHERE id = $1`,
    [userId],
  );
  if (!rows[0]) {
    const err = new Error('User not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }
  
  // Decrypt full_name
  const user = rows[0];
  if (user.full_name) {
    user.full_name = await cryptoService.decrypt('user_pii', user.full_name, user.pii_key_version);
  }
  delete user.pii_key_version; // Don't expose key version to client
  
  return user;
}

async function updateProfile(userId, { fullName, displayName }) {
  // Encrypt fullName if provided
  let encryptedName = null;
  let keyVersion = null;
  if (fullName) {
    const encrypted = await cryptoService.encrypt('user_pii', fullName);
    encryptedName = encrypted.ciphertext;
    keyVersion = encrypted.keyVersion;
  }
  
  const { rows } = await db.query(
    `UPDATE users
     SET full_name    = COALESCE($1, full_name),
         pii_key_version = COALESCE($2, pii_key_version),
         display_name = COALESCE($3, display_name),
         updated_at   = NOW()
     WHERE id = $4
     RETURNING id, email, full_name, display_name, pii_key_version`,
    [encryptedName, keyVersion, displayName || null, userId],
  );
  
  // Decrypt full_name for response
  const user = rows[0];
  if (user.full_name) {
    user.full_name = await cryptoService.decrypt('user_pii', user.full_name, user.pii_key_version);
  }
  delete user.pii_key_version;
  
  return user;
}

async function listPaymentMethods(userId) {
  const { rows } = await db.query(
    `SELECT id, type, phone_number, bank_name, account_name, account_number, 
            is_default, created_at, key_version
     FROM payment_methods WHERE user_id = $1 AND is_active = TRUE
     ORDER BY is_default DESC, created_at ASC`,
    [userId],
  );
  
  // Decrypt sensitive fields
  for (const row of rows) {
    if (row.phone_number && row.key_version) {
      row.phone_number = await cryptoService.decrypt('payment', row.phone_number, row.key_version);
    }
    if (row.account_name && row.key_version) {
      row.account_name = await cryptoService.decrypt('payment', row.account_name, row.key_version);
    }
    if (row.account_number && row.key_version) {
      row.account_number = await cryptoService.decrypt('payment', row.account_number, row.key_version);
    }
    delete row.key_version; // Don't expose to client
  }
  
  return rows;
}

async function addPaymentMethod(userId, { type, phoneNumber, bankName, accountName, accountNumber, isDefault }) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    if (isDefault) {
      // Un-default existing methods of same type
      await client.query(
        `UPDATE payment_methods SET is_default = FALSE
         WHERE user_id = $1 AND type = $2`,
        [userId, type],
      );
    }

    // Encrypt sensitive fields (only if they have values)
    let payKeyVersion = null;
    
    const { ciphertext: encPhone, keyVersion: phoneKeyVersion } = phoneNumber 
      ? await cryptoService.encrypt('payment', phoneNumber) 
      : { ciphertext: null, keyVersion: null };
    
    const { ciphertext: encAcctName, keyVersion: nameKeyVersion } = accountName 
      ? await cryptoService.encrypt('payment', accountName) 
      : { ciphertext: null, keyVersion: null };
    
    const { ciphertext: encAcctNum, keyVersion: numKeyVersion } = accountNumber 
      ? await cryptoService.encrypt('payment', accountNumber) 
      : { ciphertext: null, keyVersion: null };
    
    // Use any non-null key version (they should all be the same for active DEK)
    payKeyVersion = phoneKeyVersion || nameKeyVersion || numKeyVersion;
    
    // Generate HMAC for searchable fields (only if they have values)
    const phoneHmac = phoneNumber ? await cryptoService.hmacField(phoneNumber) : null;
    const acctHmac = accountNumber ? await cryptoService.hmacField(accountNumber) : null;

    const { rows } = await client.query(
      `INSERT INTO payment_methods
         (user_id, type, phone_number, bank_name, account_name, account_number, 
          phone_number_hmac, account_number_hmac, key_version, is_default)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING *`,
      [userId, type, encPhone, bankName || null, encAcctName, encAcctNum, 
       phoneHmac, acctHmac, payKeyVersion, isDefault || false],
    );

    await client.query('COMMIT');
    
    // Decrypt for response
    const method = rows[0];
    if (method.phone_number && method.key_version) {
      method.phone_number = await cryptoService.decrypt('payment', method.phone_number, method.key_version);
    }
    if (method.account_name && method.key_version) {
      method.account_name = await cryptoService.decrypt('payment', method.account_name, method.key_version);
    }
    if (method.account_number && method.key_version) {
      method.account_number = await cryptoService.decrypt('payment', method.account_number, method.key_version);
    }
    delete method.key_version;
    delete method.phone_number_hmac;
    delete method.account_number_hmac;
    
    return method;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function deletePaymentMethod(userId, methodId) {
  const { rowCount } = await db.query(
    `UPDATE payment_methods SET is_active = FALSE
     WHERE id = $1 AND user_id = $2`,
    [methodId, userId],
  );
  if (rowCount === 0) {
    const err = new Error('Payment method not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }
}

async function setDefaultPaymentMethod(userId, methodId) {
  const { rows } = await db.query(
    'SELECT type FROM payment_methods WHERE id = $1 AND user_id = $2 AND is_active = TRUE',
    [methodId, userId],
  );
  if (!rows[0]) {
    const err = new Error('Payment method not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `UPDATE payment_methods SET is_default = FALSE WHERE user_id = $1 AND type = $2`,
      [userId, rows[0].type],
    );
    await client.query(`UPDATE payment_methods SET is_default = TRUE WHERE id = $1`, [methodId]);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function syncTransactionStatus(transaction) {
  if (!transaction || !['pending', 'processing'].includes(transaction.status) || !transaction.mpesa_checkout_request_id) {
    return transaction;
  }
  
  const createdTime = new Date(transaction.created_at).getTime();
  const nowTime = Date.now();
  const elapsedMs = nowTime - createdTime;
  const elapsedMinutes = elapsedMs / 60000;
  
  try {
    const data = await mpesaService.stkPushQuery(transaction.mpesa_checkout_request_id);
    
    // If ResultCode is present in response, it has completed or failed
    if (data && data.ResultCode !== undefined && data.ResultCode !== null) {
      const resultCode = String(data.ResultCode);
      const resultDesc = data.ResultDesc || 'No description provided';
      
      if (resultCode === '0') {
        const mpesaReceipt = 'SYNC-' + transaction.mpesa_checkout_request_id.slice(-8).toUpperCase();
        
        const { rows } = await db.query(
          `UPDATE transactions
           SET status = 'completed',
               mpesa_transaction_id = COALESCE(mpesa_transaction_id, $1),
               updated_at = NOW()
           WHERE id = $2 AND status IN ('pending', 'processing')
           RETURNING *`,
          [mpesaReceipt, transaction.id]
        );
        if (rows[0]) {
          logger.info('STK Push synced to COMPLETED', { transactionId: transaction.id });
          await handleTransactionCommission(db, transaction.id);
          return rows[0];
        }
      } else {
        const newStatus = resultCode === '1032' ? 'cancelled' : 'failed';
        let failureReason = resultDesc;
        if (resultCode === '1') {
          failureReason = 'Insufficient funds in your M-Pesa account.';
        } else if (resultCode === '2001') {
          failureReason = 'Incorrect M-Pesa PIN entered.';
        } else if (resultCode === '1032') {
          failureReason = 'Transaction was cancelled by the user.';
        } else if (resultCode === '1037') {
          failureReason = 'Transaction timed out (no response received from handset).';
        }
        
        const { rows } = await db.query(
          `UPDATE transactions
           SET status = $1,
               failure_reason = $2,
               updated_at = NOW()
           WHERE id = $3 AND status IN ('pending', 'processing')
           RETURNING *`,
          [newStatus, failureReason, transaction.id]
        );
        if (rows[0]) {
          logger.info('STK Push synced to FAILED/CANCELLED', { transactionId: transaction.id, resultCode, failureReason });
          return rows[0];
        }
      }
    }
  } catch (err) {
    logger.debug('STK query sync error / still pending', { transactionId: transaction.id, error: err.message });
    
    if (elapsedMs >= 25000) {
      const failureReason = 'Transaction timed out. M-Pesa payment was not received within 25 seconds. Please try again.';
      const { rows } = await db.query(
        `UPDATE transactions
         SET status = 'failed',
             failure_reason = $1,
             updated_at = NOW()
         WHERE id = $2 AND status IN ('pending', 'processing')
         RETURNING *`,
        [failureReason, transaction.id]
      );
      if (rows[0]) {
        logger.warn('STK Push marked as FAILED due to 25-second timeout', { transactionId: transaction.id });
        return rows[0];
      }
    }
  }
  
  return transaction;
}

async function listTransactions(userId, { page = 1, limit = 20, type, status } = {}) {
  // Whitelist validation to prevent SQL injection
  const validTypes = ['deposit', 'withdrawal']; // Fixed: was 'withdraw', 'transfer'
  const validStatuses = ['pending', 'processing', 'completed', 'failed', 'cancelled']; // Fixed: added 'processing', removed 'in_progress'
  
  if (type && !validTypes.includes(type)) {
    const err = new Error('Invalid transaction type.');
    err.type = 'VALIDATION';
    throw err;
  }
  
  if (status && !validStatuses.includes(status)) {
    const err = new Error('Invalid transaction status.');
    err.type = 'VALIDATION';
    throw err;
  }

  // Sync pending transactions first
  try {
    const { rows: pendingTxns } = await db.query(
      `SELECT id, status, mpesa_checkout_request_id, created_at
       FROM transactions
       WHERE user_id = $1 AND status IN ('pending', 'processing') AND type = 'deposit' AND mpesa_checkout_request_id IS NOT NULL`,
      [userId]
    );
    for (const txn of pendingTxns) {
      await syncTransactionStatus(txn);
    }
  } catch (err) {
    logger.error('Error syncing pending transactions', { error: err.message, userId });
  }
  
  const offset = (page - 1) * limit;
  const conditions = ['user_id = $1'];
  const params = [userId];

  if (type)   { conditions.push(`type = $${params.push(type)}`); }
  if (status) { conditions.push(`status = $${params.push(status)}`); }

  const where = conditions.join(' AND ');

  const [data, count] = await Promise.all([
    db.query(
      `SELECT id, type, status, amount_kes, amount_usd, exchange_rate,
              mpesa_transaction_id, b2c_transaction_id,
              destination_type, failure_reason, created_at,
              mpesa_phone, mpesa_checkout_request_id
       FROM transactions WHERE ${where}
       ORDER BY created_at DESC
       LIMIT $${params.push(limit)} OFFSET $${params.push(offset)}`,
      params,
    ),
    db.query(`SELECT COUNT(*) FROM transactions WHERE ${where}`, params.slice(0, params.length - 2)),
  ]);

  return {
    transactions: data.rows,
    total: parseInt(count.rows[0].count),
    page,
    limit,
  };
}

async function verifyPassword(userId, password) {
  const { rows } = await db.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
  if (!rows[0]) {
    const err = new Error('User not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }
  return bcrypt.compare(password, rows[0].password_hash);
}

async function changePassword(userId, verificationToken, newPassword) {
  // 1. Verify OTP token
  const verified = otpService.parseVerificationToken(verificationToken);
  if (!verified || verified.purpose !== 'password_reset') {
    const err = new Error('Invalid or expired verification token.');
    err.type = 'VALIDATION';
    throw err;
  }

  const destination = verified.destination;

  // 2. Fetch user to check email match
  const { rows: userRows } = await db.query('SELECT email FROM users WHERE id = $1', [userId]);
  if (!userRows[0]) {
    const err = new Error('User not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }

  const userEmail = userRows[0].email;
  let isAuthorizedDestination = (destination.toLowerCase() === userEmail.toLowerCase());

  if (!isAuthorizedDestination) {
    // Check if destination matches any of the user's active payment methods (phone numbers)
    const phoneHmac = await cryptoService.hmacField(destination);
    const { rows: pmRows } = await db.query(
      `SELECT id FROM payment_methods
       WHERE user_id = $1 AND phone_number_hmac = $2 AND is_active = TRUE`,
      [userId, phoneHmac]
    );
    if (pmRows.length > 0) {
      isAuthorizedDestination = true;
    }
  }

  if (!isAuthorizedDestination) {
    const err = new Error('Verification destination does not match user profile.');
    err.type = 'UNAUTHORIZED';
    throw err;
  }

  // 3. Hash and update password (using BCRYPT_ROUNDS = 12)
  const passwordHash = await bcrypt.hash(newPassword, 12);
  
  await db.query(
    'UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2',
    [passwordHash, userId]
  );
  
  logger.info('User password changed successfully via profile', { userId });
}

async function getEarnings(userId) {
  const { rows: userRows } = await db.query(
    'SELECT referral_earnings, referral_code FROM users WHERE id = $1',
    [userId]
  );
  const user = userRows[0];
  if (!user) {
    return { earnings: 0, referralsCount: 0, terms: 'No referral agreement found.' };
  }

  const { rows: configRows } = await db.query(
    `SELECT division_type, reward_value, split_percentage_user, split_percentage_us, expiry_amount, expiry_date, fixed_split_cap 
     FROM referral_configs 
     WHERE user_id = $1 AND is_active = TRUE`,
    [userId]
  );
  const config = configRows[0];

  let terms = 'Default Referral Agreement: Flat reward of 50.00 KES per referral.';
  if (config) {
    if (config.division_type === 'flat_with_expiry_amount') {
      terms = `Flat reward of ${parseFloat(config.reward_value || 0).toFixed(2)} KES per referral, up to a total earnings limit of ${config.expiry_amount ? parseFloat(config.expiry_amount).toFixed(2) + ' KES' : 'None'}.`;
    } else if (config.division_type === 'flat_with_expiry_date') {
      const dateStr = config.expiry_date ? new Date(config.expiry_date).toLocaleDateString() : 'Never';
      terms = `Flat reward of ${parseFloat(config.reward_value || 0).toFixed(2)} KES per referral, expiring on ${dateStr}.`;
    } else if (config.division_type === 'fixed_split') {
      terms = `Fixed split agreement: ${parseFloat(config.split_percentage_user || 0).toFixed(2)}% to partner, ${parseFloat(config.split_percentage_us || 0).toFixed(2)}% to us, up to a split cap of ${config.fixed_split_cap ? parseFloat(config.fixed_split_cap).toFixed(2) + ' KES' : 'None'}.`;
    }
  }

  const { rows: countRows } = await db.query(
    'SELECT COUNT(*) AS count FROM affiliate_redemptions WHERE referrer_id = $1',
    [userId]
  );

  return {
    earnings: Number(user.referral_earnings || 0),
    referralsCount: Number(countRows[0].count),
    terms: terms,
    referralCode: user.referral_code || '',
  };
}

async function getActiveReferralSettings(client, referrerId, referralCode) {
  // 1. Look up custom configuration in referral_configs table
  const { rows: configRows } = await client.query(
    `SELECT division_type, reward_value, split_percentage_user, split_percentage_us, expiry_amount, expiry_date, fixed_split_cap 
     FROM referral_configs 
     WHERE referral_code = $1 AND is_active = TRUE`,
    [referralCode]
  );

  if (configRows.length > 0) {
    const config = configRows[0];
    
    // Check Date Expiry
    if (config.division_type === 'flat_with_expiry_date' && config.expiry_date) {
      if (new Date() > new Date(config.expiry_date)) {
        return { type: 'expired', value: 0 };
      }
    }
    
    // Check Amount/Revenue Share Expiry
    if ((config.division_type === 'flat_with_expiry_amount' || config.division_type === 'fixed_split') && config.expiry_amount) {
      const { rows: sumRows } = await client.query(
        'SELECT COALESCE(SUM(commission_kes), 0) AS total_earned FROM affiliate_redemptions WHERE referrer_id = $1',
        [referrerId]
      );
      const totalEarned = parseFloat(sumRows[0].total_earned);
      if (totalEarned >= parseFloat(config.expiry_amount)) {
        return { type: 'expired', value: 0 };
      }
    }

    return {
      type: config.division_type,
      value: config.reward_value ? parseFloat(config.reward_value) : 0.00,
      split_percentage_user: config.split_percentage_user ? parseFloat(config.split_percentage_user) : 0.00,
      split_percentage_us: config.split_percentage_us ? parseFloat(config.split_percentage_us) : 0.00,
      expiry_amount: config.expiry_amount ? parseFloat(config.expiry_amount) : null,
      expiry_date: config.expiry_date || null,
      fixed_split_cap: config.fixed_split_cap ? parseFloat(config.fixed_split_cap) : null,
    };
  }

  // 2. Fall back to custom_referral_codes table (legacy)
  const { rows: customRows } = await client.query(
    `SELECT reward_type, reward_value, expiry_amount, expiry_date 
     FROM custom_referral_codes 
     WHERE code = $1`,
    [referralCode]
  );

  if (customRows.length > 0) {
    const config = customRows[0];
    
    // Check Date Expiry
    if (config.reward_type === 'flat_date_limit' && config.expiry_date) {
      if (new Date() > new Date(config.expiry_date)) {
        return { type: 'expired', value: 0 };
      }
    }
    
    // Check Amount/Revenue Share Expiry
    if ((config.reward_type === 'flat_amount_limit' || config.reward_type === 'revenue_share_limit') && config.expiry_amount) {
      const { rows: sumRows } = await client.query(
        'SELECT COALESCE(SUM(commission_kes), 0) AS total_earned FROM affiliate_redemptions WHERE referrer_id = $1',
        [referrerId]
      );
      const totalEarned = parseFloat(sumRows[0].total_earned);
      if (totalEarned >= parseFloat(config.expiry_amount)) {
        return { type: 'expired', value: 0 };
      }
    }

    return {
      type: config.reward_type,
      value: parseFloat(config.reward_value),
      expiry_amount: config.expiry_amount ? parseFloat(config.expiry_amount) : null
    };
  }

  // 3. Fall back to global configuration if no custom configuration exists
  const { rows: globalRows } = await client.query(
    "SELECT key, value FROM app_config WHERE key IN ('referral_type', 'referral_value')"
  );
  let type = 'flat';
  let value = 50.00;
  globalRows.forEach(r => {
    if (r.key === 'referral_type') type = r.value;
    if (r.key === 'referral_value') value = parseFloat(r.value);
  });

  return { type, value, expiry_amount: null };
}

async function handleTransactionCommission(client, transactionId) {
  try {
    // 1. Lock and update transaction to mark commission as processed.
    // If it was already processed or not completed, this will return 0 rows.
    const { rows: txnRows } = await client.query(
      `UPDATE transactions 
       SET commission_processed = TRUE 
       WHERE id = $1 AND status = 'completed' AND commission_processed = FALSE
       RETURNING user_id, amount_kes`,
      [transactionId]
    );
    const txn = txnRows[0];
    if (!txn) return; // Already processed or not completed

    // 2. Check if this user (referee) was referred by someone
    const { rows: redempRows } = await client.query(
      'SELECT referrer_id, referral_code FROM affiliate_redemptions WHERE referee_id = $1',
      [txn.user_id]
    );
    if (redempRows.length === 0) return; // Not a referred user
    const redemp = redempRows[0];

    // 3. Get configuration settings
    const settings = await getActiveReferralSettings(client, redemp.referrer_id, redemp.referral_code);

    if (
      settings.type === 'percentage' || 
      settings.type === 'revenue_share_limit' || 
      settings.type === 'fixed_split'
    ) {
      let commission = 0.00;
      if (settings.type === 'fixed_split') {
        commission = parseFloat(txn.amount_kes) * (settings.split_percentage_user / 100);
      } else {
        commission = parseFloat(txn.amount_kes) * (settings.value / 100);
      }
      
      // If we have an amount limit or cap, adjust to stay under the limit
      const cap = settings.type === 'fixed_split' ? settings.fixed_split_cap : settings.expiry_amount;
      if (cap) {
        const { rows: sumRows } = await client.query(
          'SELECT COALESCE(SUM(commission_kes), 0) AS total_earned FROM affiliate_redemptions WHERE referrer_id = $1',
          [redemp.referrer_id]
        );
        const totalEarned = parseFloat(sumRows[0].total_earned);
        const remaining = cap - totalEarned;
        if (remaining <= 0) {
          commission = 0.00;
        } else if (commission > remaining) {
          commission = remaining;
        }
      }

      if (commission > 0) {
        // Increment commission_kes in affiliate_redemptions
        await client.query(
          `UPDATE affiliate_redemptions 
           SET commission_kes = commission_kes + $1 
           WHERE referee_id = $2`,
          [commission, txn.user_id]
        );

        // Increment referral_earnings in users
        await client.query(
          `UPDATE users 
           SET referral_earnings = referral_earnings + $1 
           WHERE id = $2`,
          [commission, redemp.referrer_id]
        );

        logger.info('Affiliate transaction commission applied', { 
          refereeId: txn.user_id, 
          amountKes: txn.amount_kes, 
          commission 
        });
      }
    }
  } catch (err) {
    logger.error('Error calculating transaction commission', { transactionId, error: err.message });
  }
}

async function getReferralProfile(userId) {
  const { rows: userRows } = await db.query(
    'SELECT referral_code, referred_by, referral_earnings FROM users WHERE id = $1',
    [userId]
  );
  const user = userRows[0];
  if (!user) {
    const err = new Error('User not found.');
    err.type = 'NOT_FOUND';
    throw err;
  }

  const { rows: configRows } = await db.query(
    'SELECT id, referral_code, division_type, reward_value, split_percentage_user, split_percentage_us, expiry_amount, expiry_date, fixed_split_cap, is_active, created_at, updated_at FROM referral_configs WHERE user_id = $1',
    [userId]
  );
  const config = configRows[0];

  return {
    referral_code: user.referral_code || '',
    referred_by: user.referred_by || '',
    referral_earnings: parseFloat(user.referral_earnings || 0).toFixed(2),
    config: config || null
  };
}

module.exports = {
  getProfile,
  updateProfile,
  listPaymentMethods,
  addPaymentMethod,
  deletePaymentMethod,
  setDefaultPaymentMethod,
  listTransactions,
  syncTransactionStatus,
  verifyPassword,
  changePassword,
  getEarnings,
  handleTransactionCommission,
  getReferralProfile,
};
