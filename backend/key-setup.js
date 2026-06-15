'use strict';

/**
 * key-setup.js — Run EXACTLY ONCE to initialise the encryption system.
 *
 * What it does:
 *   1. Generates a cryptographically random 256-bit master KEK
 *   2. Generates a random 256-bit DEK for every data domain
 *   3. Encrypts each DEK with the master KEK (AES-256-GCM) and stores in DB
 *   4. Emails the raw master KEK to georgesmars8@gmail.com so you never lose it
 *   5. Prints the MASTER_KEY value to add to your .env
 *
 * Usage:
 *   node key-setup.js
 *
 * After running:
 *   1. Copy the printed MASTER_KEY line into backend/.env
 *   2. Restart the backend:  npm run dev
 *   3. Run migrations if you haven't:  node migrate.js
 *
 * ⚠️  DO NOT run this again unless you want to REPLACE all keys.
 *     Existing encrypted data will become UNREADABLE if you do.
 *     To rotate keys, use key-rotation.js instead.
 */

require('dotenv').config();

const crypto     = require('crypto');
const { Pool }   = require('pg');
const nodemailer = require('nodemailer');
const resolveDbSsl = require('./src/config/db-ssl');

// ── Config ────────────────────────────────────────────────────────────────────

const ALGORITHM     = 'aes-256-gcm';
const KEY_BYTES     = 32;   // 256-bit keys
const IV_BYTES      = 16;   // 128-bit IV (GCM standard)
const ROTATION_DAYS = 7;    // keys expire after 7 days → triggers auto-rotation

const DOMAINS = [
  'user_pii',      // encrypts users.full_name
  'payment',       // encrypts payment_methods.phone_number / account_name / account_number
  'external',      // encrypts users.deriv_access_token / deriv_refresh_token
  'payment_hmac',  // HMAC key for searchable phone/account sidecars
];

// ── DB pool ───────────────────────────────────────────────────────────────────

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl:      resolveDbSsl(),
});

// ── Crypto helpers ────────────────────────────────────────────────────────────

function encryptDek(dekBuf, kek) {
  const iv     = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, kek, iv);
  const data   = Buffer.concat([cipher.update(dekBuf), cipher.final()]);
  const tag    = cipher.getAuthTag();
  return {
    encrypted_dek: data.toString('hex'),
    dek_iv:        iv.toString('hex'),
    dek_tag:       tag.toString('hex'),
  };
}

// ── Email ─────────────────────────────────────────────────────────────────────

async function emailMasterKey(masterKeyHex) {
  const transporter = nodemailer.createTransport({
    host:   process.env.SMTP_HOST,
    port:   parseInt(process.env.SMTP_PORT || '587'),
    secure: parseInt(process.env.SMTP_PORT || '587') === 465,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });

  const generated = new Date().toISOString();

  await transporter.sendMail({
    from:    `"K-PESA Security" <${process.env.EMAIL_FROM}>`,
    to:      'georgesmars8@gmail.com',
    subject: '🔐 [ACTION REQUIRED] K-PESA Master Encryption Key',
    html: `
      <div style="font-family:sans-serif;max-width:620px;margin:auto">
        <div style="background:#c00;color:#fff;padding:16px 24px;border-radius:8px 8px 0 0">
          <h2 style="margin:0">⚠️ K-PESA Master Encryption Key</h2>
        </div>
        <div style="border:2px solid #c00;border-top:none;padding:24px;border-radius:0 0 8px 8px">
          <p><strong>This key protects all sensitive data in K-PESA. If lost, encrypted data cannot be recovered.</strong></p>

          <p>Add the following line to your <code>backend/.env</code> file:</p>

          <div style="background:#111;color:#0f0;font-family:monospace;padding:16px;border-radius:6px;word-break:break-all;font-size:14px;margin:16px 0">
            MASTER_KEY=${masterKeyHex}
          </div>

          <table style="width:100%;border-collapse:collapse;font-size:13px;margin-top:16px">
            <tr style="background:#f5f5f5">
              <td style="padding:8px 12px;font-weight:bold">Generated</td>
              <td style="padding:8px 12px">${generated}</td>
            </tr>
            <tr>
              <td style="padding:8px 12px;font-weight:bold">Key length</td>
              <td style="padding:8px 12px">256-bit (AES-256-GCM)</td>
            </tr>
            <tr style="background:#f5f5f5">
              <td style="padding:8px 12px;font-weight:bold">Rotation</td>
              <td style="padding:8px 12px">Domain DEKs rotate every ${ROTATION_DAYS} days automatically</td>
            </tr>
          </table>

          <div style="background:#fff3cd;border:1px solid #ffc107;padding:12px 16px;border-radius:6px;margin-top:20px;font-size:13px">
            <strong>After saving the key:</strong>
            <ol style="margin:8px 0;padding-left:20px">
              <li>Delete this email from your inbox and trash</li>
              <li>Store the key in a password manager (1Password, Bitwarden, etc.)</li>
              <li>Never commit MASTER_KEY to git</li>
            </ol>
          </div>
        </div>
      </div>
    `,
  });

  console.log('  ✅  Master key emailed to georgesmars8@gmail.com');
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const client = await pool.connect();
  try {
    // Guard: refuse to run if any active keys already exist
    const { rows: existing } = await client.query(
      'SELECT COUNT(*) FROM encryption_keys WHERE is_active = TRUE',
    );
    if (parseInt(existing[0].count) > 0) {
      console.error('\n❌  Active encryption keys already exist in the database.');
      console.error('    Use key-rotation.js to rotate keys, not this script.\n');
      process.exit(1);
    }

    console.log('\n🔑  Generating master KEK...');
    const masterKey    = crypto.randomBytes(KEY_BYTES);
    const masterKeyHex = masterKey.toString('hex');

    console.log('\n──────────────────────────────────────────────────────');
    console.log('  Add this to backend/.env:');
    console.log(`  MASTER_KEY=${masterKeyHex}`);
    console.log('──────────────────────────────────────────────────────\n');

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + ROTATION_DAYS);

    await client.query('BEGIN');

    for (const domain of DOMAINS) {
      const dek = crypto.randomBytes(KEY_BYTES);
      const { encrypted_dek, dek_iv, dek_tag } = encryptDek(dek, masterKey);

      await client.query(
        `INSERT INTO encryption_keys
           (domain, version, encrypted_dek, dek_iv, dek_tag, is_active, expires_at)
         VALUES ($1, 1, $2, $3, $4, TRUE, $5)`,
        [domain, encrypted_dek, dek_iv, dek_tag, expiresAt],
      );

      // Log the initial setup in rotation log
      await client.query(
        `INSERT INTO key_rotation_log
           (domain, old_version, new_version, records_updated, triggered_by, status, completed_at)
         VALUES ($1, NULL, 1, 0, 'setup', 'completed', NOW())`,
        [domain],
      );

      console.log(`  ✅  DEK created → domain: ${domain}  version: 1  expires: ${expiresAt.toISOString()}`);
    }

    await client.query('COMMIT');

    // Email the master key
    console.log('\n📧  Emailing master key...');
    await emailMasterKey(masterKeyHex);

    console.log('\n🚀  Setup complete!');
    console.log('    Next steps:');
    console.log('    1. Add MASTER_KEY to backend/.env (shown above)');
    console.log('    2. node migrate.js   ← if not already run');
    console.log('    3. npm run dev       ← restart the backend\n');

  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('\n❌  Setup failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

main();
