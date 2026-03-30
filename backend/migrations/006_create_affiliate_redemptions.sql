-- Migration 006: affiliate_redemptions table
CREATE TABLE IF NOT EXISTS affiliate_redemptions (
  id              UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id     UUID           NOT NULL REFERENCES users(id),
  referee_id      UUID           NOT NULL REFERENCES users(id),
  referral_code   VARCHAR(20)    NOT NULL,
  commission_kes  NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
  paid_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  UNIQUE(referee_id)  -- each user can only redeem one referral
);

CREATE INDEX IF NOT EXISTS idx_aff_referrer ON affiliate_redemptions(referrer_id);
