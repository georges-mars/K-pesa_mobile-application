-- Migration 010: device_biometrics table
CREATE TABLE IF NOT EXISTS device_biometrics (
  id                     SERIAL       PRIMARY KEY,
  user_id                UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id              VARCHAR(255) NOT NULL UNIQUE,
  device_name            VARCHAR(255),
  is_active              BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_biometrics_device_id ON device_biometrics(device_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_device_biometrics_user_id   ON device_biometrics(user_id) WHERE is_active = TRUE;
