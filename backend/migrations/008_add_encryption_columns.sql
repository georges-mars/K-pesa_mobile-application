-- Migration 008: prepare existing tables for field-level encryption
--
-- Encrypted columns store:  iv_hex:tag_hex:ciphertext_hex  (AES-256-GCM)
-- Each encrypted row tracks WHICH key version encrypted it so rotation works.
-- HMAC sidecar columns allow searching on encrypted phone/account numbers
-- without ever decrypting the full dataset.
--
-- Fields encrypted:
--   users.full_name                  → user_pii DEK
--   users.deriv_access_token         → external  DEK  (was already TEXT)
--   users.deriv_refresh_token        → external  DEK  (was already TEXT)
--   payment_methods.phone_number     → payment   DEK  + HMAC sidecar
--   payment_methods.account_name     → payment   DEK
--   payment_methods.account_number   → payment   DEK  + HMAC sidecar

-- ── users ─────────────────────────────────────────────────────────────────────

-- full_name now stores encrypted ciphertext; widen the column to TEXT
ALTER TABLE users
  ALTER COLUMN full_name TYPE TEXT;

-- Which user_pii DEK version encrypted full_name on this row
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS pii_key_version INTEGER;

-- Which external DEK version encrypted deriv_access/refresh_token on this row
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS ext_key_version INTEGER;


-- ── payment_methods ──────────────────────────────────────────────────────────

-- Widen columns that will hold ciphertext (32:32:N hex chars, always > original length)
ALTER TABLE payment_methods
  ALTER COLUMN phone_number   TYPE TEXT,
  ALTER COLUMN account_number TYPE TEXT;

-- Which payment DEK version encrypted the sensitive columns on this row
ALTER TABLE payment_methods
  ADD COLUMN IF NOT EXISTS key_version          INTEGER;

-- Deterministic HMAC of the plaintext phone number.
-- Used for fast existence/match queries without decrypting.
-- Computed as: HMAC-SHA256(lower(trim(phone)), payment_hmac_DEK)
ALTER TABLE payment_methods
  ADD COLUMN IF NOT EXISTS phone_number_hmac    VARCHAR(64);

-- Same pattern for bank account number
ALTER TABLE payment_methods
  ADD COLUMN IF NOT EXISTS account_number_hmac  VARCHAR(64);

-- Fast lookup indexes on HMAC sidecars
CREATE INDEX IF NOT EXISTS idx_pm_phone_hmac
  ON payment_methods(phone_number_hmac)
  WHERE phone_number_hmac IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pm_acct_hmac
  ON payment_methods(account_number_hmac)
  WHERE account_number_hmac IS NOT NULL;
