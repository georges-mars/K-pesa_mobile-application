-- Migration 016: Create pending_referral_changes table
CREATE TABLE IF NOT EXISTS pending_referral_changes (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  code           VARCHAR(50)  NOT NULL,
  email          VARCHAR(255),
  phone          VARCHAR(50),
  reward_type    VARCHAR(50)  NOT NULL,
  reward_value   NUMERIC(10, 2) NOT NULL,
  expiry_amount  NUMERIC(12, 2),
  expiry_date    TIMESTAMPTZ,
  otp_code       VARCHAR(10)  NOT NULL,
  expires_at     TIMESTAMPTZ  NOT NULL,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
