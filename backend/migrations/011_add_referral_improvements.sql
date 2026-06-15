-- Migration 011: Add custom referral codes and track signup referral code
CREATE TABLE IF NOT EXISTS custom_referral_codes (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(50)  NOT NULL UNIQUE,
  email       VARCHAR(255) NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Add referred_by_code to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by_code VARCHAR(50);
