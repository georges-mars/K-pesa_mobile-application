-- Migration 012: Create app_config table for referral and application configuration
CREATE TABLE IF NOT EXISTS app_config (
  key         VARCHAR(50)  PRIMARY KEY,
  value       TEXT         NOT NULL,
  description TEXT,
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Insert default referral configuration
INSERT INTO app_config (key, value, description)
VALUES 
  ('referral_type', 'flat', 'Type of referral reward: flat or percentage'),
  ('referral_value', '50.00', 'Referral reward value. KES amount if flat, or percentage (0-100) of transaction if percentage')
ON CONFLICT (key) DO NOTHING;
