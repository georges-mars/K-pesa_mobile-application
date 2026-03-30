'use strict';

const db     = require('../config/database');
const logger = require('../config/logger');
const cryptoService = require('./crypto.service');

async function getProfile(userId) {
  const { rows } = await db.query(
    `SELECT id, email, full_name, display_name, deriv_email, deriv_name, deriv_account,
            binance_id, referral_code, is_verified, created_at, pii_key_version
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
              destination_type, failure_reason, created_at
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

module.exports = {
  getProfile,
  updateProfile,
  listPaymentMethods,
  addPaymentMethod,
  deletePaymentMethod,
  setDefaultPaymentMethod,
  listTransactions,
};
