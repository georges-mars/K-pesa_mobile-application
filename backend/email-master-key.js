/**
 * Email Current Master Key
 * Sends the MASTER_KEY from .env to georgesmars8@gmail.com
 */

const nodemailer = require('nodemailer');
require('dotenv').config();

async function emailMasterKey() {
  const masterKey = process.env.MASTER_KEY;

  if (!masterKey || masterKey.length !== 64) {
    console.error('❌ No valid MASTER_KEY found in .env');
    console.error('   Expected 64-character hex string');
    process.exit(1);
  }

  console.log('📧 Emailing MASTER_KEY to georgesmars8@gmail.com...\n');

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT),
    secure: false,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS.replace(/\s/g, ''),
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
      <p>Your K-PESA database has been reset and new encryption keys have been generated.</p>

      <div class="warning">
        <strong>⚠️ CRITICAL:</strong> Store this key securely! Without it, your encrypted data cannot be accessed.
      </div>

      <h3 style="color: #37C215; margin-top: 25px;">Master Encryption Key (MASTER_KEY)</h3>
      <div class="key-box">
        ${masterKey}
      </div>

      <div class="steps">
        <h3 style="color: #37C215; margin-top: 0;">What This Key Does:</h3>
        <p>This master key encrypts/decrypts all sensitive data in K-PESA:</p>
        <ul style="margin: 10px 0 0 0; padding-left: 20px;">
          <li><strong>User PII:</strong> Full names, phone numbers</li>
          <li><strong>Payment Info:</strong> M-Pesa/Airtel numbers, bank accounts</li>
          <li><strong>Deriv Tokens:</strong> OAuth access/refresh tokens</li>
          <li><strong>External IDs:</strong> Binance UIDs, Deriv account IDs</li>
        </ul>
      </div>

      <div class="warning">
        <strong>🔒 Security Best Practices:</strong>
        <ul style="margin: 10px 0 0 0; padding-left: 20px;">
          <li><strong>Backup:</strong> Store in 1Password, Bitwarden, or secure vault</li>
          <li><strong>Never commit to git:</strong> .env files should be in .gitignore</li>
          <li><strong>Production keys:</strong> Use different keys for dev/staging/prod</li>
          <li><strong>Key rotation:</strong> Run <code>node key-rotation.js</code> weekly</li>
        </ul>
      </div>

      <p style="margin-top: 25px; color: #6c757d; font-size: 14px;">
        Sent on: ${new Date().toLocaleString()}<br>
        Database: ${process.env.DB_NAME}<br>
        Environment: ${process.env.NODE_ENV}
      </p>

      <div style="background: #d1ecf1; border: 1px solid #bee5eb; padding: 12px 16px; border-radius: 6px; margin-top: 20px; font-size: 13px;">
        <strong>📝 Action Required:</strong>
        <ol style="margin: 8px 0; padding-left: 20px;">
          <li>Save this key to your password manager</li>
          <li>Verify it matches <code>backend/.env</code> MASTER_KEY</li>
          <li>Delete this email after backing up</li>
          <li>Test signup flow to ensure encryption works</li>
        </ol>
      </div>
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
      to: 'georgesmars8@gmail.com',
      subject: '🔐 K-PESA Master Encryption Key - SECURE BACKUP',
      html: emailBody,
    });

    console.log('✅ Email sent successfully!');
    console.log('📬 Message ID:', info.messageId);
    console.log('📧 Sent to: georgesmars8@gmail.com\n');
    console.log('═'.repeat(70));
    console.log('✅ Check your inbox at georgesmars8@gmail.com');
    console.log('═'.repeat(70));
  } catch (error) {
    console.error('❌ Error sending email:', error.message);
    console.log('\n⚠️  EMAIL FAILED! Here is your MASTER_KEY (save it now):\n');
    console.log('═'.repeat(70));
    console.log(masterKey);
    console.log('═'.repeat(70));
    console.log('\nThis key is already in your backend/.env file\n');
  }
}

emailMasterKey();
