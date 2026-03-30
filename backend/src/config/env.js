'use strict';

const Joi = require('joi');

const schema = Joi.object({
  NODE_ENV:                  Joi.string().valid('development', 'production', 'test').default('development'),
  PORT:                      Joi.number().default(3000),
  BASE_URL:                  Joi.string().uri().required(),

  // JWT
  JWT_SECRET:                Joi.string().min(32).required(),
  JWT_EXPIRES_IN:            Joi.string().default('15m'),
  REFRESH_TOKEN_EXPIRES_DAYS: Joi.number().default(7),

  // PostgreSQL
  DB_HOST:     Joi.string().required(),
  DB_PORT:     Joi.number().default(5432),
  DB_NAME:     Joi.string().required(),
  DB_USER:     Joi.string().required(),
  DB_PASSWORD: Joi.string().required(),

  // Safaricom Daraja
  MPESA_CONSUMER_KEY:        Joi.string().required(),
  MPESA_CONSUMER_SECRET:     Joi.string().required(),
  MPESA_SHORT_CODE:          Joi.string().required(),
  MPESA_PASSKEY:             Joi.string().required(),
  MPESA_INITIATOR_NAME:      Joi.string().required(),
  MPESA_SECURITY_CREDENTIAL: Joi.string().required(),
  MPESA_ENV:                 Joi.string().valid('sandbox', 'production').default('sandbox'),

  // Africa's Talking
  AT_USERNAME: Joi.string().required(),
  AT_API_KEY:  Joi.string().required(),

  // Email (nodemailer)
  SMTP_HOST:   Joi.string().required(),
  SMTP_PORT:   Joi.number().default(587),
  SMTP_USER:   Joi.string().required(),
  SMTP_PASS:   Joi.string().required(),
  EMAIL_FROM:  Joi.string().email().required(),

  // Deriv — only the App ID is needed; Deriv returns tokens directly in the OAuth redirect
  DERIV_APP_ID: Joi.string().required(),

  // Master Key Encryption Key — 64-char hex (32 bytes).
  // Generated once by: node key-setup.js
  MASTER_KEY: Joi.string().length(64).required(),
}).unknown(true); // allow other env vars (PATH, HOME, etc.)

function validateEnv() {
  const { error } = schema.validate(process.env, { abortEarly: false });
  if (error) {
    const missing = error.details.map(d => d.message).join('\n  ');
    console.error(`\n[env] Missing or invalid environment variables:\n  ${missing}\n`);
    process.exit(1);
  }
}

module.exports = { validateEnv };
