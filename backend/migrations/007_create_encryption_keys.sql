-- Migration 007: encryption key management tables
-- Implements a 2-layer key hierarchy:
--   Master KEK (in .env)  →  encrypts DEKs
--   Domain DEKs (in this table)  →  encrypt actual data fields

-- One row per domain per version.
-- Domains: 'user_pii' | 'payment' | 'external' | 'payment_hmac'
CREATE TABLE IF NOT EXISTS encryption_keys (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  domain        VARCHAR(50)  NOT NULL,
  version       INTEGER      NOT NULL,

  -- The DEK itself, encrypted with the master KEK using AES-256-GCM
  encrypted_dek TEXT         NOT NULL,   -- hex-encoded ciphertext
  dek_iv        VARCHAR(64)  NOT NULL,   -- hex-encoded 16-byte IV
  dek_tag       VARCHAR(64)  NOT NULL,   -- hex-encoded 16-byte GCM auth tag

  is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ  NOT NULL,   -- 7 days from creation; triggers rotation

  -- Set when a newer version supersedes this one
  rotated_at    TIMESTAMPTZ,

  UNIQUE(domain, version)
);

-- Fast lookup: find the active key for a domain
CREATE INDEX IF NOT EXISTS idx_enc_keys_active
  ON encryption_keys(domain, is_active, expires_at);


-- Audit trail for every key rotation event
CREATE TABLE IF NOT EXISTS key_rotation_log (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  domain           VARCHAR(50) NOT NULL,
  old_version      INTEGER,                  -- NULL on first-ever setup
  new_version      INTEGER     NOT NULL,
  records_updated  INTEGER     NOT NULL DEFAULT 0,
  triggered_by     VARCHAR(50) NOT NULL DEFAULT 'auto',   -- 'auto' | 'manual' | 'emergency'
  status           VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
  started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at     TIMESTAMPTZ,
  error_message    TEXT
);
