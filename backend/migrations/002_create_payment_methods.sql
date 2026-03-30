-- Migration 002: payment_methods table
CREATE TABLE IF NOT EXISTS payment_methods (
  id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type           VARCHAR(20)  NOT NULL CHECK (type IN ('mpesa', 'airtel', 'bank')),

  -- Phone (M-Pesa / Airtel)
  phone_number   VARCHAR(20),   -- E.164 format: +254712345678

  -- Bank
  bank_name      VARCHAR(100),
  account_name   VARCHAR(255),
  account_number VARCHAR(50),

  is_default     BOOLEAN      NOT NULL DEFAULT FALSE,
  is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_user ON payment_methods(user_id);

-- Only one default per payment type per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_default_per_type
  ON payment_methods(user_id, type)
  WHERE is_default = TRUE;
