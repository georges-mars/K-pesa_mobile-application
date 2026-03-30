-- ============================================================================
-- Migration: Add encryption support columns
-- Description: Adds key_version and HMAC columns for encryption implementation
-- Run: psql -U kpesa_user -d kpesa < add_encryption_columns.sql
-- ============================================================================

-- Add key version tracking to users table
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS pii_key_version INTEGER,
  ADD COLUMN IF NOT EXISTS ext_key_version INTEGER;

-- Add HMAC and key version columns to payment_methods table
ALTER TABLE payment_methods 
  ADD COLUMN IF NOT EXISTS phone_number_hmac TEXT,
  ADD COLUMN IF NOT EXISTS account_number_hmac TEXT,
  ADD COLUMN IF NOT EXISTS key_version INTEGER;

-- Add index on HMAC fields for faster lookups
CREATE INDEX IF NOT EXISTS idx_payment_methods_phone_hmac 
  ON payment_methods(phone_number_hmac) 
  WHERE phone_number_hmac IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payment_methods_account_hmac 
  ON payment_methods(account_number_hmac) 
  WHERE account_number_hmac IS NOT NULL;

-- Log migration
INSERT INTO migrations_run (filename, applied_at)
VALUES ('add_encryption_columns.sql', NOW())
ON CONFLICT (filename) DO NOTHING;

-- Verification
SELECT 
  column_name, 
  data_type, 
  is_nullable 
FROM information_schema.columns 
WHERE table_name IN ('users', 'payment_methods') 
  AND column_name IN ('pii_key_version', 'ext_key_version', 'phone_number_hmac', 'account_number_hmac', 'key_version')
ORDER BY table_name, column_name;
