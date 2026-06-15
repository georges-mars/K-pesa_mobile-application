-- Migration 018: Update referred_by column to VARCHAR(50) to store literal referral codes
-- 1. Drop foreign key constraint
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_referred_by_fkey;

-- 2. Alter referred_by column type to VARCHAR(50)
ALTER TABLE users ALTER COLUMN referred_by TYPE VARCHAR(50);
