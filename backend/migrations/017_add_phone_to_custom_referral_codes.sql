-- Migration 017: Add phone column to custom_referral_codes table
ALTER TABLE custom_referral_codes ADD COLUMN IF NOT EXISTS phone VARCHAR(50);
