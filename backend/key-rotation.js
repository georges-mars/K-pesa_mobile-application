'use strict';

/**
 * key-rotation.js — Weekly DEK rotation job.
 *
 * Run this every 7 days via OS cron (or Windows Task Scheduler).
 * It is safe to run more frequently — it only rotates domains whose
 * active DEK is within 24 hours of expiry (or already expired).
 *
 * Cron example (every Sunday at 02:00):
 *   0 2 * * 0  cd /path/to/backend && node key-rotation.js >> logs/rotation.log 2>&1
 *
 * What it does per domain:
 *   1. Check if the active DEK is expiring within 24 h
 *   2. Generate a new DEK, encrypt it with the master KEK, store in DB
 *   3. Re-encrypt every affected DB row with the new DEK
 *   4. Deactivate the old DEK
 *   5. Log the event and email the admin with a summary
 *
 * Domains and the DB rows they touch:
 *   user_pii     → users.full_name          (filter: pii_key_version = old)
 *   payment      → payment_methods.*         (filter: key_version = old)
 *   external     → users.deriv_*_token       (filter: ext_key_version = old)
 *   payment_hmac → payment_methods HMACs     (ALL rows — HMAC key changed)
 */

require('dotenv').config();

const crypto     = require('crypto');
const { Pool }   = require('pg');
const nodemailer = require('nodemailer');
const resolveDbSsl = require('./src/config/db-ssl');

// ── Config ────────────────────────────────────────────────────────────────────

const ALGORITHM      = 'aes-256-gcm';
const KEY_BYTES      = 32;
const IV_BYTES       = 16;
const ROTATION_DAYS  = 7;
const ROTATE_AHEAD_H = 24;   // rotate if expiry is within this many hours
const BATCH_SIZE     = 100;  // rows re-encrypted per DB transaction

// ── DB ────────────────────────────────────────────────────────────────────────

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl:      resolveDbSsl(),
});

// ── Crypto helpers ────────────────────────────────────────────────────────────

function getMasterKey() {
  const hex = process.env.MASTER_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error('MASTER_KEY missing or invalid. Add it to .env and re-run.');
  }
  return Buffer.from(hex, 'hex');
}

function encryptDek(dekBuf) {
  const kek    = getMasterKey();
  const iv     = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, kek, iv);
  const data   = Buffer.concat([cipher.update(dekBuf), cipher.final()]);
  const tag    = cipher.getAuthTag();
  return {
    encrypted_dek: data.toString('hex'),
    dek_iv:        iv.toString('hex'),
    dek_tag:       tag.toString('hex'),
    rawDek:        dekBuf,
  };
}

function decryptDek(encryptedHex, ivHex, tagHex) {
  const kek      = getMasterKey();
  const decipher = crypto.createDecipheriv(ALGORITHM, kek, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedHex, 'hex')),
    decipher.final(),
  ]);
}

async function loadDek(client, domain, version) {
  const { rows } = await client.query(
    'SELECT encrypted_dek, dek_iv, dek_tag FROM encryption_keys WHERE domain=$1 AND version=$2',
    [domain, version],
  );
  if (!rows[0]) throw new Error(`DEK not found: ${domain} v${version}`);
  return decryptDek(rows[0].encrypted_dek, rows[0].dek_iv, rows[0].dek_tag);
}

function encryptField(plaintext, dek) {
  if (!plaintext) return null;
  const iv     = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, dek, iv);
  const data   = Buffer.concat([cipher.update(Buffer.from(plaintext, 'utf8')), cipher.final()]);
  const tag    = cipher.getAuthTag();
  return [iv.toString('hex'), tag.toString('hex'), data.toString('hex')].join(':');
}

function decryptField(ciphertext, dek) {
  if (!ciphertext) return null;
  const [ivHex, tagHex, dataHex] = ciphertext.split(':');
  const decipher = crypto.createDecipheriv(ALGORITHM, dek, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  return Buffer.concat([
    decipher.update(Buffer.from(dataHex, 'hex')),
    decipher.final(),
  ]).toString('utf8');
}

function hmacValue(value, hmacDek) {
  if (!value) return null;
  return crypto.createHmac('sha256', hmacDek)
    .update(String(value).toLowerCase().trim())
    .digest('hex');
}

// ── Domain-specific re-encryption ─────────────────────────────────────────────

async function rotateUserPii(client, oldVersion, oldDek, newDek, newVersion) {
  let offset = 0, total = 0;
  for (;;) {
    const { rows } = await client.query(
      `SELECT id, full_name FROM users
       WHERE pii_key_version = $1 AND full_name IS NOT NULL
       ORDER BY id LIMIT $2 OFFSET $3`,
      [oldVersion, BATCH_SIZE, offset],
    );
    if (rows.length === 0) break;

    for (const row of rows) {
      const plain     = decryptField(row.full_name, oldDek);
      const encrypted = encryptField(plain, newDek);
      await client.query(
        'UPDATE users SET full_name = $1, pii_key_version = $2, updated_at = NOW() WHERE id = $3',
        [encrypted, newVersion, row.id],
      );
    }
    total  += rows.length;
    offset += rows.length;
    if (rows.length < BATCH_SIZE) break;
  }
  return total;
}

async function rotatePayment(client, oldVersion, oldDek, newDek, newVersion, hmacDek) {
  let offset = 0, total = 0;
  for (;;) {
    const { rows } = await client.query(
      `SELECT id, phone_number, account_name, account_number
       FROM payment_methods
       WHERE key_version = $1
       ORDER BY id LIMIT $2 OFFSET $3`,
      [oldVersion, BATCH_SIZE, offset],
    );
    if (rows.length === 0) break;

    for (const row of rows) {
      const plainPhone  = decryptField(row.phone_number,   oldDek);
      const plainAcctN  = decryptField(row.account_name,   oldDek);
      const plainAcctNo = decryptField(row.account_number, oldDek);

      await client.query(
        `UPDATE payment_methods SET
           phone_number        = $1,
           account_name        = $2,
           account_number      = $3,
           phone_number_hmac   = $4,
           account_number_hmac = $5,
           key_version         = $6
         WHERE id = $7`,
        [
          encryptField(plainPhone,  newDek),
          encryptField(plainAcctN,  newDek),
          encryptField(plainAcctNo, newDek),
          hmacValue(plainPhone,  hmacDek),
          hmacValue(plainAcctNo, hmacDek),
          newVersion,
          row.id,
        ],
      );
    }
    total  += rows.length;
    offset += rows.length;
    if (rows.length < BATCH_SIZE) break;
  }
  return total;
}

async function rotateExternal(client, oldVersion, oldDek, newDek, newVersion) {
  let offset = 0, total = 0;
  for (;;) {
    const { rows } = await client.query(
      `SELECT id, deriv_access_token, deriv_refresh_token FROM users
       WHERE ext_key_version = $1 AND deriv_access_token IS NOT NULL
       ORDER BY id LIMIT $2 OFFSET $3`,
      [oldVersion, BATCH_SIZE, offset],
    );
    if (rows.length === 0) break;

    for (const row of rows) {
      const plainAccess  = decryptField(row.deriv_access_token,  oldDek);
      const plainRefresh = decryptField(row.deriv_refresh_token, oldDek);
      await client.query(
        `UPDATE users SET
           deriv_access_token  = $1,
           deriv_refresh_token = $2,
           ext_key_version     = $3,
           updated_at          = NOW()
         WHERE id = $4`,
        [
          encryptField(plainAccess,  newDek),
          encryptField(plainRefresh, newDek),
          newVersion,
          row.id,
        ],
      );
    }
    total  += rows.length;
    offset += rows.length;
    if (rows.length < BATCH_SIZE) break;
  }
  return total;
}

// payment_hmac rotation: re-compute ALL HMAC sidecars with the new HMAC key.
// We need the current payment DEK to decrypt plaintext first.
async function rotatePaymentHmac(client, newHmacDek) {
  // Get the current active payment DEK (not rotating now, but needed to decrypt)
  const { rows: dekRows } = await client.query(
    `SELECT version, encrypted_dek, dek_iv, dek_tag FROM encryption_keys
     WHERE domain = 'payment' AND is_active = TRUE ORDER BY version DESC LIMIT 1`,
  );
  if (!dekRows[0]) return 0;
  const paymentDek = decryptDek(dekRows[0].encrypted_dek, dekRows[0].dek_iv, dekRows[0].dek_tag);

  let offset = 0, total = 0;
  for (;;) {
    const { rows } = await client.query(
      `SELECT id, phone_number, account_number FROM payment_methods
       WHERE phone_number IS NOT NULL OR account_number IS NOT NULL
       ORDER BY id LIMIT $1 OFFSET $2`,
      [BATCH_SIZE, offset],
    );
    if (rows.length === 0) break;

    for (const row of rows) {
      const plainPhone  = decryptField(row.phone_number,   paymentDek);
      const plainAcctNo = decryptField(row.account_number, paymentDek);
      await client.query(
        `UPDATE payment_methods SET
           phone_number_hmac   = $1,
           account_number_hmac = $2
         WHERE id = $3`,
        [hmacValue(plainPhone, newHmacDek), hmacValue(plainAcctNo, newHmacDek), row.id],
      );
    }
    total  += rows.length;
    offset += rows.length;
    if (rows.length < BATCH_SIZE) break;
  }
  return total;
}

// ── Core rotation logic ───────────────────────────────────────────────────────

async function rotateDomain(client, domain) {
  const windowMs   = ROTATE_AHEAD_H * 60 * 60 * 1000;
  const threshold  = new Date(Date.now() + windowMs);

  const { rows } = await client.query(
    `SELECT id, version, encrypted_dek, dek_iv, dek_tag, expires_at FROM encryption_keys
     WHERE domain = $1 AND is_active = TRUE ORDER BY version DESC LIMIT 1`,
    [domain],
  );
  if (!rows[0]) {
    console.log(`  [${domain}]  No active key found — skipping`);
    return null;
  }

  const current = rows[0];
  if (new Date(current.expires_at) > threshold) {
    console.log(`  [${domain}]  OK — expires ${current.expires_at}`);
    return null;
  }

  console.log(`  [${domain}]  Rotating v${current.version} → v${current.version + 1} ...`);
  const logId      = (await client.query(
    `INSERT INTO key_rotation_log (domain, old_version, new_version, triggered_by, status)
     VALUES ($1,$2,$3,'auto','in_progress') RETURNING id`,
    [domain, current.version, current.version + 1],
  )).rows[0].id;

  try {
    // Generate new DEK
    const newRawDek  = crypto.randomBytes(KEY_BYTES);
    const newVersion = current.version + 1;
    const expiresAt  = new Date();
    expiresAt.setDate(expiresAt.getDate() + ROTATION_DAYS);
    const { encrypted_dek, dek_iv, dek_tag } = encryptDek(newRawDek);

    // Store new DEK (still not active yet — old one stays active during re-encryption)
    await client.query(
      `INSERT INTO encryption_keys (domain, version, encrypted_dek, dek_iv, dek_tag, is_active, expires_at)
       VALUES ($1,$2,$3,$4,$5,FALSE,$6)`,
      [domain, newVersion, encrypted_dek, dek_iv, dek_tag, expiresAt],
    );

    const oldDek = decryptDek(current.encrypted_dek, current.dek_iv, current.dek_tag);

    // Re-encrypt rows depending on domain
    let updated = 0;
    if (domain === 'user_pii') {
      updated = await rotateUserPii(client, current.version, oldDek, newRawDek, newVersion);
    } else if (domain === 'payment') {
      const { rows: hmacRow } = await client.query(
        `SELECT encrypted_dek, dek_iv, dek_tag FROM encryption_keys
         WHERE domain='payment_hmac' AND is_active=TRUE ORDER BY version DESC LIMIT 1`,
      );
      const hmacDek = hmacRow[0]
        ? decryptDek(hmacRow[0].encrypted_dek, hmacRow[0].dek_iv, hmacRow[0].dek_tag)
        : newRawDek; // fallback
      updated = await rotatePayment(client, current.version, oldDek, newRawDek, newVersion, hmacDek);
    } else if (domain === 'external') {
      updated = await rotateExternal(client, current.version, oldDek, newRawDek, newVersion);
    } else if (domain === 'payment_hmac') {
      updated = await rotatePaymentHmac(client, newRawDek);
    }

    // Activate new DEK, deactivate old
    await client.query(
      'UPDATE encryption_keys SET is_active=TRUE WHERE domain=$1 AND version=$2',
      [domain, newVersion],
    );
    await client.query(
      'UPDATE encryption_keys SET is_active=FALSE, rotated_at=NOW() WHERE id=$1',
      [current.id],
    );

    // Complete log
    await client.query(
      `UPDATE key_rotation_log
       SET status='completed', records_updated=$1, completed_at=NOW() WHERE id=$2`,
      [updated, logId],
    );

    console.log(`  [${domain}]  ✅ Done — ${updated} rows re-encrypted`);
    return { domain, oldVersion: current.version, newVersion, updated };

  } catch (err) {
    await client.query(
      `UPDATE key_rotation_log SET status='failed', error_message=$1, completed_at=NOW() WHERE id=$2`,
      [err.message, logId],
    );
    throw err;
  }
}

// ── Email summary ─────────────────────────────────────────────────────────────

async function emailSummary(results) {
  if (results.length === 0) return;

  const transporter = nodemailer.createTransport({
    host:   process.env.SMTP_HOST,
    port:   parseInt(process.env.SMTP_PORT || '587'),
    secure: parseInt(process.env.SMTP_PORT || '587') === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });

  const rows = results.map(r =>
    `<tr>
       <td style="padding:6px 12px">${r.domain}</td>
       <td style="padding:6px 12px;text-align:center">v${r.oldVersion} → v${r.newVersion}</td>
       <td style="padding:6px 12px;text-align:center">${r.updated}</td>
     </tr>`,
  ).join('');

  await transporter.sendMail({
    from:    `"K-PESA Security" <${process.env.EMAIL_FROM}>`,
    to:      process.env.ADMIN_EMAIL || process.env.EMAIL_FROM,
    subject: `✅ K-PESA Key Rotation Complete — ${new Date().toDateString()}`,
    html: `
      <div style="font-family:sans-serif;max-width:560px;margin:auto">
        <h2 style="color:#37c215">K-PESA — Encryption Key Rotation</h2>
        <p>The following domain keys were rotated on <strong>${new Date().toISOString()}</strong>:</p>
        <table style="width:100%;border-collapse:collapse;font-size:13px">
          <thead>
            <tr style="background:#37c215;color:#fff">
              <th style="padding:8px 12px;text-align:left">Domain</th>
              <th style="padding:8px 12px">Version</th>
              <th style="padding:8px 12px">Rows re-encrypted</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
        <p style="color:#666;font-size:12px;margin-top:16px">K-PESA automated key management</p>
      </div>
    `,
  });
  console.log('  📧  Summary emailed to georgesmars8@gmail.com');
}

// ── Main ──────────────────────────────────────────────────────────────────────

const DOMAINS = ['user_pii', 'payment', 'external', 'payment_hmac'];

async function main() {
  console.log(`\n🔄  K-PESA Key Rotation — ${new Date().toISOString()}\n`);
  const client  = await pool.connect();
  const rotated = [];

  try {
    for (const domain of DOMAINS) {
      const result = await rotateDomain(client, domain);
      if (result) rotated.push(result);
    }

    if (rotated.length === 0) {
      console.log('\n✅  All keys are current — no rotation needed.\n');
    } else {
      console.log(`\n✅  Rotated ${rotated.length} domain(s).\n`);
      await emailSummary(rotated);
    }

  } catch (err) {
    console.error('\n❌  Rotation error:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

main();
