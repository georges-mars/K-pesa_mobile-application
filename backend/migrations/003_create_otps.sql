-- Migration 003: otps table
CREATE TABLE IF NOT EXISTS otps (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  destination   VARCHAR(255) NOT NULL,  -- E.164 phone or email address
  otp_hash      VARCHAR(255) NOT NULL,  -- bcrypt(otp, rounds=8)
  purpose       VARCHAR(50)  NOT NULL
    CHECK (purpose IN ('signup', 'login', 'password_reset', 'withdrawal')),
  attempt_count INTEGER      NOT NULL DEFAULT 0,
  expires_at    TIMESTAMPTZ  NOT NULL,
  used_at       TIMESTAMPTZ,            -- set when successfully verified
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otps_destination ON otps(destination, purpose);
CREATE INDEX IF NOT EXISTS idx_otps_expires_at  ON otps(expires_at);
