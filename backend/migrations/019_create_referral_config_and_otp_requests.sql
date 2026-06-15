-- Migration 019: Create referral_config and otp_requests tables, alter users
-- 1. Make referral_code column nullable on users table
ALTER TABLE users ALTER COLUMN referral_code DROP NOT NULL;

-- 2. Add referral_earnings column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_earnings NUMERIC(12, 2) NOT NULL DEFAULT 0.00;

-- 3. Create referral_config table
CREATE TABLE IF NOT EXISTS referral_config (
  id             UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID           UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reward_type    VARCHAR(50)    NOT NULL,
  percentage     NUMERIC(5, 2),
  expiry_amount  NUMERIC(12, 2),
  expiry_date    TIMESTAMPTZ,
  fixed_amount   NUMERIC(12, 2),
  created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- 4. Create otp_requests table
CREATE TABLE IF NOT EXISTS otp_requests (
  id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  otp_code               VARCHAR(10)  NOT NULL,
  purpose                VARCHAR(100) NOT NULL,
  proposed_referral_code VARCHAR(50)  NOT NULL,
  config                 JSONB        NOT NULL,
  expires_at             TIMESTAMPTZ  NOT NULL,
  used                   BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
