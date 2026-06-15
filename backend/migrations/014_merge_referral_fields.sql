-- Migration 014: Merge referral fields by removing redundant referred_by_code column
ALTER TABLE users DROP COLUMN IF EXISTS referred_by_code;
