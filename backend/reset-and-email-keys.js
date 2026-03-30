/**
 * Complete Database Reset + Key Regeneration + Email Notification
 * Run with: node reset-and-email-keys.js
 */

const { Pool } = require('pg');
const crypto = require('crypto');
const nodemailer = require('nodemailer');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// ─── Step 1: Clear Database ───────────────────────────────────────────────────

async function clearDatabase() {
  console.log('📦 Step 1: Clearing database...\n');

  try {
    // Truncate all tables in correct order to handle foreign keys
    // CASCADE will automatically handle foreign key constraints
    await pool.query('TRUNCATE TABLE affiliate_redemptions RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared affiliate_redemptions');

    await pool.query('TRUNCATE TABLE transactions RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared transactions');

    await pool.query('TRUNCATE TABLE refresh_tokens RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared refresh_tokens');

    await pool.query('TRUNCATE TABLE otps RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared otps');

    await pool.query('TRUNCATE TABLE payment_methods RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared payment_methods');

    await pool.query('TRUNCATE TABLE users RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared users');

    await pool.query('TRUNCATE TABLE encryption_keys RESTART IDENTITY CASCADE');
    console.log('  ✓ Cleared encryption_keys\n');

    console.log('✅ Database cleared successfully!\n');
  } catch (error) {
    console.error('❌ Error clearing database:', error.message);
    throw error;
  }
}

// ─── Step 2: Regenerate Encryption Keys ───────────────────────────────────────

async function regenerateKeys() {
  console.log('🔐 Step 2: Regenerating encryption keys...\n');

  const masterKey = crypto.randomBytes(32).toString('hex');
  console.log('  ✓ Generated new MASTER_KEY\n');

  const DOMAINS = ['user_pii', 'payment', 'external', 'payment_hmac'];
  const ROTATION_DAYS = 7;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + ROTATION_DAYS);

  try {
    for (const domain of DOMAINS) {
      // Generate a random DEK for this domain
      const dek = crypto.randomBytes(32);

      // Encrypt the DEK with the master key
      const iv = crypto.randomBytes(16);
      const cipher = crypto.createCipheriv(
        'aes-256-gcm',
        Buffer.from(masterKey, 'hex'),
        iv,
      );
      const encrypted = Buffer.concat([cipher.update(dek), cipher.final()]);
      const tag = cipher.getAuthTag();

      // Store in database
      await pool.query(
        `INSERT INTO encryption_keys
           (domain, version, encrypted_dek, dek_iv, dek_tag, is_active, expires_at)
         VALUES ($1, 1, $2, $3, $4, TRUE, $5)`,
        [
          domain,
          encrypted.toString('hex'),
          iv.toString('hex'),
          tag.toString('hex'),
          expiresAt,
        ],
      );

      // Log in rotation table
      await pool.query(
        `INSERT INTO key_rotation_log
           (domain, old_version, new_version, records_updated, triggered_by, status, completed_at)
         VALUES ($1, NULL, 1, 0, 'reset', 'completed', NOW())`,
        [domain],
      );

      console.log(`  ✓ Created DEK for domain: ${domain} (version 1)`);
    }

    console.log('\n✅ Encryption keys regenerated successfully!\n');
    return masterKey;
  } catch (error) {
    console.error('❌ Error storing keys:', error.message);
    throw error;
  }
}

// ─── Step 3: Send Email ────────────────────────────────────────────────────────

async function sendEmail(masterKey) {
  console.log('📧 Step 3: Sending keys to email...\n');

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT),
    secure: false,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS.replace(/\s/g, ''), // Remove spaces
    },
  });

  const emailBody = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #37C215 0%, #2a9410 100%); color: white; padding: 30px; border-radius: 10px 10px 0 0; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { background: #f8f9fa; padding: 30px; border: 1px solid #dee2e6; }
    .key-box { background: #fff; border: 2px solid #37C215; border-radius: 8px; padding: 20px; margin: 20px 0; font-family: 'Courier New', monospace; word-break: break-all; }
    .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
    .steps { background: #fff; padding: 20px; border-radius: 8px; margin: 20px 0; }
    .steps ol { padding-left: 20px; }
    .steps li { margin: 10px 0; }
    .footer { background: #343a40; color: #adb5bd; padding: 20px; text-align: center; border-radius: 0 0 10px 10px; font-size: 12px; }
    code { background: #e9ecef; padding: 2px 6px; border-radius: 3px; font-family: 'Courier New', monospace; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔐 K-PESA Encryption Keys</h1>
      <p style="margin: 10px 0 0 0; opacity: 0.9;">Database Reset Complete</p>
    </div>

    <div class="content">
      <p>Your K-PESA database has been completely reset and new encryption keys have been generated.</p>

      <div class="warning">
        <strong>⚠️ CRITICAL:</strong> Store this key securely! Without it, your encrypted data cannot be accessed.
      </div>

      <h3 style="color: #37C215; margin-top: 25px;">Master Encryption Key (MASTER_KEY)</h3>
      <div class="key-box">
        ${masterKey}
      </div>

      <div class="steps">
        <h3 style="color: #37C215; margin-top: 0;">Next Steps:</h3>
        <ol>
          <li>Open your <code>backend/.env</code> file</li>
          <li>Replace the <code>MASTER_KEY</code> value with the key above</li>
          <li>Restart your backend server: <code>npm start</code></li>
          <li>Test the signup flow from your Flutter app</li>
          <li><strong>Store this email securely</strong> (password manager, secure vault)</li>
          <li><strong>Delete this email</strong> after backing up the key</li>
        </ol>
      </div>

      <div class="warning">
        <strong>🔒 Security Best Practices:</strong>
        <ul style="margin: 10px 0 0 0; padding-left: 20px;">
          <li>Never commit this key to version control</li>
          <li>Use different keys for production and development</li>
          <li>Rotate keys periodically using <code>node key-rotation.js</code></li>
          <li>Keep backups of your keys in a secure location</li>
        </ul>
      </div>

      <p style="margin-top: 25px; color: #6c757d; font-size: 14px;">
        Generated on: ${new Date().toLocaleString()}<br>
        Database: ${process.env.DB_NAME}<br>
        Environment: ${process.env.NODE_ENV}
      </p>
    </div>

    <div class="footer">
      <p style="margin: 0;">K-PESA Automated Key Management System</p>
      <p style="margin: 5px 0 0 0;">This is an automated message. Do not reply.</p>
    </div>
  </div>
</body>
</html>
  `.trim();

  try {
    const info = await transporter.sendMail({
      from: `"K-PESA Security" <${process.env.EMAIL_FROM}>`,
      to: process.env.SMTP_USER,
      subject: '🔐 K-PESA New Encryption Keys - Action Required',
      html: emailBody,
    });

    console.log(`  ✓ Email sent successfully!`);
    console.log(`  📬 Message ID: ${info.messageId}\n`);
    console.log(`✅ Keys sent to: ${process.env.SMTP_USER}\n`);
  } catch (error) {
    console.error('❌ Error sending email:', error.message);
    console.log('\n⚠️  EMAIL FAILED! Here is your MASTER_KEY (save it now):\n');
    console.log('═'.repeat(70));
    console.log(masterKey);
    console.log('═'.repeat(70));
    console.log('\nCopy this key to your .env file as MASTER_KEY=<key>\n');
  }
}

// ─── Main Execution ────────────────────────────────────────────────────────────

async function main() {
  console.log('\n🚀 K-PESA Database Reset & Key Regeneration');
  console.log('═'.repeat(70));
  console.log('⚠️  WARNING: This will DELETE ALL DATA from your database!');
  console.log('Database:', process.env.DB_NAME);
  console.log('Email will be sent to:', process.env.SMTP_USER);
  console.log('═'.repeat(70));
  console.log('\nStarting in 3 seconds... Press Ctrl+C to cancel\n');

  await new Promise(resolve => setTimeout(resolve, 3000));

  try {
    // Step 1: Clear database
    await clearDatabase();

    // Step 2: Regenerate keys
    const masterKey = await regenerateKeys();

    // Step 3: Send email
    await sendEmail(masterKey);

    console.log('═'.repeat(70));
    console.log('✅ ALL DONE! Check your email for the new MASTER_KEY');
    console.log('═'.repeat(70));
    console.log('\nNext steps:');
    console.log('  1. Check email:', process.env.SMTP_USER);
    console.log('  2. Update backend/.env with new MASTER_KEY');
    console.log('  3. Restart your backend server');
    console.log('  4. Test signup from your Flutter app\n');

  } catch (error) {
    console.error('\n❌ FATAL ERROR:', error.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

main();
