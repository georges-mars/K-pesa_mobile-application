-- Migration 001: users table
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
  id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  email                  VARCHAR(255) NOT NULL UNIQUE,
  password_hash          VARCHAR(255) NOT NULL,
  full_name              VARCHAR(255),

  -- Deriv OAuth profile
  deriv_email            VARCHAR(255),
  deriv_name             VARCHAR(255),
  deriv_account          VARCHAR(50),           -- e.g. CR10125517
  deriv_access_token     TEXT,                  -- encrypted with AES via pgcrypto
  deriv_refresh_token    TEXT,                  -- encrypted with AES via pgcrypto
  deriv_token_expires_at TIMESTAMPTZ,

  -- Binance
  binance_id             VARCHAR(20),

  -- Account status
  is_verified            BOOLEAN      NOT NULL DEFAULT FALSE,
  is_active              BOOLEAN      NOT NULL DEFAULT TRUE,

  -- Referral
  referral_code          VARCHAR(20)  NOT NULL UNIQUE,
  referred_by            UUID         REFERENCES users(id),

  created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email         ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);
CREATE INDEX IF NOT EXISTS idx_users_deriv_account ON users(deriv_account) WHERE deriv_account IS NOT NULL;
