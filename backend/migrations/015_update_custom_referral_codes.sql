-- Migration 015: Add config columns to custom_referral_codes table and make email unique
ALTER TABLE custom_referral_codes ADD COLUMN IF NOT EXISTS reward_type VARCHAR(50) NOT NULL DEFAULT 'flat_amount_limit';
ALTER TABLE custom_referral_codes ADD COLUMN IF NOT EXISTS reward_value NUMERIC(10, 2) NOT NULL DEFAULT 50.00;
ALTER TABLE custom_referral_codes ADD COLUMN IF NOT EXISTS expiry_amount NUMERIC(12, 2);
ALTER TABLE custom_referral_codes ADD COLUMN IF NOT EXISTS expiry_date TIMESTAMPTZ;

-- Make email unique to support easy upserts per email
ALTER TABLE custom_referral_codes DROP CONSTRAINT IF EXISTS unique_custom_ref_email;
ALTER TABLE custom_referral_codes ADD CONSTRAINT unique_custom_ref_email UNIQUE (email);
