'use strict';

const crypto       = require('crypto');
const bcrypt       = require('bcryptjs');
const db           = require('../config/database');
const emailService = require('../services/email.service');
const smsService   = require('../services/sms.service');
const cryptoService = require('../services/crypto.service');
const logger       = require('../config/logger');

async function getReferralCodes(req, res, next) {
  try {
    const { rows } = await db.query(
      `SELECT u.id, u.email, u.referral_code, u.referral_earnings, u.created_at,
              c.reward_type, c.percentage, c.expiry_amount, c.expiry_date, c.fixed_amount
       FROM users u
       LEFT JOIN referral_config c ON u.id = c.user_id
       ORDER BY u.created_at DESC`
    );
    
    // Map response for frontend listing
    const mapped = rows.map(r => ({
      id: r.id,
      code: r.referral_code || 'None',
      email: r.email,
      reward_type: r.reward_type,
      reward_value: r.reward_type === 'flat_date_limit' ? r.fixed_amount : r.percentage,
      expiry_amount: r.expiry_amount,
      expiry_date: r.expiry_date,
      created_at: r.created_at
    }));
    
    res.json(mapped);
  } catch (err) {
    next(err);
  }
}

async function initiateChange(req, res, next) {
  try {
    const { proposed_code, email, phone, reward_type, percentage, expiry_amount, expiry_date, fixed_amount } = req.body;
    const formattedCode = proposed_code.trim().toUpperCase();
    const formattedEmail = email ? email.trim().toLowerCase() : null;
    const formattedPhone = phone ? phone.trim() : null;

    // 1. Find target user
    let targetUser = null;
    if (formattedEmail) {
      const { rows } = await db.query('SELECT id, email FROM users WHERE email = $1', [formattedEmail]);
      if (rows.length > 0) targetUser = rows[0];
    } else if (formattedPhone) {
      const phoneHmac = await cryptoService.hmacField(formattedPhone);
      const { rows } = await db.query(
        `SELECT u.id, u.email FROM users u 
         JOIN payment_methods pm ON u.id = pm.user_id 
         WHERE pm.phone_number_hmac = $1 AND pm.is_active = TRUE`,
        [phoneHmac]
      );
      if (rows.length > 0) targetUser = rows[0];
    }

    if (!targetUser) {
      return res.status(404).json({ error: 'Target user not found.' });
    }

    // 2. Generate 6-digit OTP
    const otpCode = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 10 * 60000); // 10 minutes from now

    const config = {
      reward_type,
      percentage: percentage === '' || percentage === null ? null : parseFloat(percentage),
      expiry_amount: expiry_amount === '' || expiry_amount === null ? null : parseFloat(expiry_amount),
      expiry_date: expiry_date === '' || expiry_date === null ? null : expiry_date,
      fixed_amount: fixed_amount === '' || fixed_amount === null ? null : parseFloat(fixed_amount),
    };

    // 3. Insert into otp_requests
    const { rows } = await db.query(
      `INSERT INTO otp_requests 
         (user_id, otp_code, purpose, proposed_referral_code, config, expires_at)
       VALUES ($1, $2, 'referral_change', $3, $4, $5)
       RETURNING id`,
      [
        targetUser.id,
        otpCode,
        formattedCode,
        JSON.stringify(config),
        expiresAt
      ]
    );
    const otpRequestId = rows[0].id;

    // 4. Format Terms Description
    let termsDesc = '';
    if (reward_type === 'flat_amount_limit') {
      termsDesc = `Flat reward of ${parseFloat(percentage || 0).toFixed(2)}% distribution per referral, up to total limit of ${expiry_amount ? parseFloat(expiry_amount).toFixed(2) + ' KES' : 'None'}.`;
    } else if (reward_type === 'flat_date_limit') {
      const dateStr = expiry_date ? new Date(expiry_date).toLocaleDateString() : 'Never';
      termsDesc = `Flat reward of ${parseFloat(fixed_amount || 50).toFixed(2)} KES per referral, expiring on ${dateStr}.`;
    } else if (reward_type === 'revenue_share_limit') {
      termsDesc = `30/70 split (70% commission to partner, 30% to us) until target limit of ${expiry_amount ? parseFloat(expiry_amount).toFixed(2) + ' KES' : 'None'} is reached.`;
    }

    // 5. Dispatch OTP
    let dispatchSuccess = false;
    if (formattedEmail) {
      dispatchSuccess = await emailService.sendReferralChangeOtpEmail(formattedEmail, formattedCode, termsDesc, otpCode);
    } else if (formattedPhone) {
      const smsBody = `K-PESA OTP: ${otpCode} to confirm change of referral code to ${formattedCode}. Terms: ${termsDesc}`;
      dispatchSuccess = await smsService.sendSms(formattedPhone, smsBody);
    }

    res.status(202).json({
      message: 'Confirmation OTP generated and dispatched.',
      otpRequestId,
      dispatched: dispatchSuccess
    });
  } catch (err) {
    next(err);
  }
}

async function confirmChange(req, res, next) {
  const client = await db.getClient();
  try {
    const { otpRequestId, otp } = req.body;

    // 1. Fetch pending request
    const { rows: otpRows } = await client.query(
      'SELECT * FROM otp_requests WHERE id = $1 AND used = FALSE',
      [otpRequestId]
    );
    const request = otpRows[0];

    if (!request) {
      return res.status(404).json({ error: 'Referral change request not found or already used.' });
    }

    if (new Date() > new Date(request.expires_at)) {
      return res.status(400).json({ error: 'Referral change request has expired.' });
    }

    if (request.otp_code !== otp) {
      return res.status(400).json({ error: 'Incorrect OTP code.' });
    }

    await client.query('BEGIN');

    // 2. Mark OTP request as used
    await client.query(
      'UPDATE otp_requests SET used = TRUE WHERE id = $1',
      [otpRequestId]
    );

    // 3. Update user's referral_code
    await client.query(
      'UPDATE users SET referral_code = $1 WHERE id = $2',
      [request.proposed_referral_code, request.user_id]
    );

    // 4. Update or Insert referral_config
    const config = typeof request.config === 'string' ? JSON.parse(request.config) : request.config;
    
    const { rows: checkRows } = await client.query(
      'SELECT id FROM referral_config WHERE user_id = $1',
      [request.user_id]
    );

    if (checkRows.length > 0) {
      await client.query(
        `UPDATE referral_config 
         SET reward_type = $1, 
             percentage = $2, 
             expiry_amount = $3, 
             expiry_date = $4,
             fixed_amount = $5,
             created_at = NOW()
         WHERE user_id = $6`,
        [
          config.reward_type, 
          config.percentage, 
          config.expiry_amount, 
          config.expiry_date,
          config.fixed_amount,
          request.user_id
        ]
      );
    } else {
      await client.query(
        `INSERT INTO referral_config 
           (user_id, reward_type, percentage, expiry_amount, expiry_date, fixed_amount) 
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          request.user_id,
          config.reward_type, 
          config.percentage, 
          config.expiry_amount, 
          config.expiry_date,
          config.fixed_amount
        ]
      );
    }

    await client.query('COMMIT');

    res.json({
      message: 'Referral configuration applied and confirmed successfully.'
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    next(err);
  } finally {
    client.release();
  }
}

async function deleteReferralCode(req, res, next) {
  const client = await db.getClient();
  try {
    const { id } = req.params;
    await client.query('BEGIN');

    // Reset user's referral_code
    await client.query(
      'UPDATE users SET referral_code = NULL WHERE id = $1',
      [id]
    );

    // Delete referral config
    await client.query(
      'DELETE FROM referral_config WHERE user_id = $1',
      [id]
    );

    await client.query('COMMIT');
    res.json({ message: 'Referral code deleted successfully.' });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    next(err);
  } finally {
    client.release();
  }
}

async function getConfig(req, res, next) {
  try {
    const { rows } = await db.query(
      "SELECT key, value FROM app_config WHERE key IN ('referral_type', 'referral_value')"
    );
    const config = {};
    rows.forEach(r => {
      config[r.key] = r.value;
    });
    res.json(config);
  } catch (err) {
    next(err);
  }
}

async function updateConfig(req, res, next) {
  const client = await db.getClient();
  try {
    const { referral_type, referral_value } = req.body;
    await client.query('BEGIN');
    await client.query(
      "UPDATE app_config SET value = $1, updated_at = NOW() WHERE key = 'referral_type'",
      [referral_type]
    );
    await client.query(
      "UPDATE app_config SET value = $1, updated_at = NOW() WHERE key = 'referral_value'",
      [String(referral_value)]
    );
    await client.query('COMMIT');
    res.json({
      message: 'Configuration updated successfully.',
      config: { referral_type, referral_value }
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    next(err);
  } finally {
    client.release();
  }
}

async function createReferral(req, res, next) {
  try {
    const {
      userId,
      customCode,
      divisionType,
      rewardValue,
      splitPercentageUser,
      splitPercentageus,
      expiryAmount,
      expiryDate,
      fixedSplitCap,
      deliveryMethod,
      destination,
    } = req.body;

    const codeUpper = customCode.trim().toUpperCase();

    // 1. Validate customCode uniqueness in both users and referral_configs tables
    const { rows: userCheck } = await db.query(
      'SELECT id FROM users WHERE referral_code = $1',
      [codeUpper]
    );
    if (userCheck.length > 0) {
      return res.status(400).json({ error: 'Custom code is already in use by another user.' });
    }

    const { rows: configCheck } = await db.query(
      'SELECT id FROM referral_configs WHERE referral_code = $1',
      [codeUpper]
    );
    if (configCheck.length > 0) {
      return res.status(400).json({ error: 'Custom code is already registered in referral configurations.' });
    }

    // 2. Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const otpHash = await bcrypt.hash(otp, 12);
    const expiresAt = new Date(Date.now() + 10 * 60000); // 10 minutes from now

    // 3. Build plain English terms based on divisionType
    let termsDesc = '';
    if (divisionType === 'flat_with_expiry_amount') {
      termsDesc = `Flat reward of ${parseFloat(rewardValue || 0).toFixed(2)} KES per referral, up to a total earnings limit of ${expiryAmount ? parseFloat(expiryAmount).toFixed(2) + ' KES' : 'None'}.`;
    } else if (divisionType === 'flat_with_expiry_date') {
      const dateStr = expiryDate ? new Date(expiryDate).toLocaleDateString() : 'Never';
      termsDesc = `Flat reward of ${parseFloat(rewardValue || 0).toFixed(2)} KES per referral, expiring on ${dateStr}.`;
    } else if (divisionType === 'fixed_split') {
      termsDesc = `Fixed split agreement: ${parseFloat(splitPercentageUser || 0).toFixed(2)}% to partner, ${parseFloat(splitPercentageus || 0).toFixed(2)}% to us, up to a split cap of ${fixedSplitCap ? parseFloat(fixedSplitCap).toFixed(2) + ' KES' : 'None'}.`;
    }

    // 4. Save to referral_otp_requests
    const configSnapshot = {
      division_type: divisionType,
      reward_value: rewardValue === '' || rewardValue === null ? null : parseFloat(rewardValue),
      split_percentage_user: splitPercentageUser === '' || splitPercentageUser === null ? null : parseFloat(splitPercentageUser),
      split_percentage_us: splitPercentageus === '' || splitPercentageus === null ? null : parseFloat(splitPercentageus),
      expiry_amount: expiryAmount === '' || expiryAmount === null ? null : parseFloat(expiryAmount),
      expiry_date: expiryDate === '' || expiryDate === null ? null : expiryDate,
      fixed_split_cap: fixedSplitCap === '' || fixedSplitCap === null ? null : parseFloat(fixedSplitCap),
    };

    const { rows: otpRows } = await db.query(
      `INSERT INTO referral_otp_requests 
         (target_user_id, new_referral_code, otp_hash, delivery_method, destination, purpose, config_snapshot, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'referral_code_change', $6, $7)
       RETURNING id`,
      [
        userId,
        codeUpper,
        otpHash,
        deliveryMethod,
        destination,
        JSON.stringify(configSnapshot),
        expiresAt
      ]
    );
    const requestId = otpRows[0].id;

    // 5. Send OTP
    let sent = false;
    if (deliveryMethod === 'email') {
      sent = await emailService.sendReferralChangeOtp(destination, codeUpper, termsDesc, otp, expiresAt);
    } else if (deliveryMethod === 'sms') {
      const smsBody = `K-PESA OTP: ${otp} to confirm change of referral code to ${codeUpper}. Terms: ${termsDesc}`;
      sent = await smsService.sendSms(destination, smsBody);
    }

    res.json({ message: 'OTP sent', requestId });
  } catch (err) {
    next(err);
  }
}

async function verifyReferralOtp(req, res, next) {
  const client = await db.getClient();
  try {
    const { requestId, otp } = req.body;

    // 1. Find the OTP request
    const { rows: otpRows } = await client.query(
      'SELECT * FROM referral_otp_requests WHERE id = $1',
      [requestId]
    );
    const request = otpRows[0];

    if (!request) {
      return res.status(404).json({ error: 'Referral change request not found.' });
    }

    if (request.used) {
      return res.status(400).json({ error: 'OTP already used.' });
    }

    if (new Date() > new Date(request.expires_at) || request.attempts >= 5) {
      return res.status(400).json({ error: 'OTP has expired.' });
    }

    // Increment attempts in DB
    const { rows: updateAttemptsRows } = await client.query(
      'UPDATE referral_otp_requests SET attempts = attempts + 1 WHERE id = $1 RETURNING attempts',
      [requestId]
    );
    const currentAttempts = updateAttemptsRows[0].attempts;

    if (currentAttempts >= 5) {
      // Mark it as expired by setting expires_at to the past
      await client.query(
        "UPDATE referral_otp_requests SET expires_at = NOW() - INTERVAL '1 second' WHERE id = $1",
        [requestId]
      );
    }

    // Verify OTP against stored hash
    const isOtpValid = await bcrypt.compare(otp, request.otp_hash);
    if (!isOtpValid) {
      if (currentAttempts >= 5) {
        return res.status(400).json({ error: 'Incorrect OTP. Maximum attempts reached. OTP is now expired.' });
      }
      return res.status(400).json({ error: `Incorrect OTP code. Attempt ${currentAttempts} of 5.` });
    }

    await client.query('BEGIN');

    // 2. Mark OTP request as used
    await client.query(
      'UPDATE referral_otp_requests SET used = TRUE WHERE id = $1',
      [requestId]
    );

    // 3. Update user's referral_code
    await client.query(
      'UPDATE users SET referral_code = $1 WHERE id = $2',
      [request.new_referral_code, request.target_user_id]
    );

    // 4. Upsert into referral_configs
    const config = typeof request.config_snapshot === 'string' 
      ? JSON.parse(request.config_snapshot) 
      : request.config_snapshot;

    const { rows: configCheck } = await client.query(
      'SELECT id FROM referral_configs WHERE user_id = $1',
      [request.target_user_id]
    );

    if (configCheck.length > 0) {
      await client.query(
        `UPDATE referral_configs 
         SET referral_code = $1,
             division_type = $2,
             reward_value = $3,
             split_percentage_user = $4,
             split_percentage_us = $5,
             expiry_amount = $6,
             expiry_date = $7,
             fixed_split_cap = $8,
             updated_at = NOW()
         WHERE user_id = $9`,
        [
          request.new_referral_code,
          config.division_type,
          config.reward_value,
          config.split_percentage_user,
          config.split_percentage_us,
          config.expiry_amount,
          config.expiry_date,
          config.fixed_split_cap,
          request.target_user_id
        ]
      );
    } else {
      await client.query(
        `INSERT INTO referral_configs 
           (referral_code, user_id, division_type, reward_value, split_percentage_user, split_percentage_us, expiry_amount, expiry_date, fixed_split_cap) 
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          request.new_referral_code,
          request.target_user_id,
          config.division_type,
          config.reward_value,
          config.split_percentage_user,
          config.split_percentage_us,
          config.expiry_amount,
          config.expiry_date,
          config.fixed_split_cap
        ]
      );
    }

    await client.query('COMMIT');

    res.json({ success: true, updatedCode: request.new_referral_code });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    next(err);
  } finally {
    client.release();
  }
}

async function getReferralUsers(req, res, next) {
  try {
    const { rows } = await db.query(
      `SELECT u.id, u.full_name, u.email, u.referral_code, u.referred_by, u.referral_earnings, u.pii_key_version,
              (SELECT EXISTS(SELECT 1 FROM referral_configs c WHERE c.user_id = u.id AND c.is_active = TRUE)) AS has_active_config,
              (SELECT phone_number FROM payment_methods pm WHERE pm.user_id = u.id AND pm.is_active = TRUE AND pm.phone_number IS NOT NULL LIMIT 1) AS phone,
              (SELECT key_version FROM payment_methods pm WHERE pm.user_id = u.id AND pm.is_active = TRUE AND pm.phone_number IS NOT NULL LIMIT 1) AS pm_key_version
       FROM users u
       ORDER BY u.created_at DESC`
    );

    const decrypted = [];
    for (const r of rows) {
      let name = null;
      if (r.full_name) {
        try {
          name = await cryptoService.decrypt('user_pii', r.full_name, r.pii_key_version);
        } catch (_) {
          name = 'Decryption Error';
        }
      }

      let phone = null;
      if (r.phone) {
        try {
          phone = await cryptoService.decrypt('payment', r.phone, r.pm_key_version);
        } catch (_) {
          phone = 'Decryption Error';
        }
      }

      decrypted.push({
        id: r.id,
        name: name,
        email: r.email,
        phone: phone,
        referral_code: r.referral_code || 'None',
        referred_by: r.referred_by || 'None',
        referral_earnings: parseFloat(r.referral_earnings || 0).toFixed(2),
        has_active_config: r.has_active_config
      });
    }

    res.json(decrypted);
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getReferralCodes,
  initiateChange,
  confirmChange,
  deleteReferralCode,
  getConfig,
  updateConfig,
  createReferral,
  verifyReferralOtp,
  getReferralUsers,
};
