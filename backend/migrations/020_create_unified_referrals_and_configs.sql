-- 1. Conditionally handle referral_id merge and cleanup
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'users' AND column_name = 'referral_id'
    ) THEN
        -- Copy non-null values of referral_id into referral_code where referral_code is currently null
        UPDATE users 
        SET referral_code = referral_id 
        WHERE referral_code IS NULL AND referral_id IS NOT NULL;
        
        -- Drop the redundant referral_id column
        ALTER TABLE users DROP COLUMN referral_id;
    END IF;
END $$;

-- 2. Add and update columns on users table
-- Check and add referred_by (stores the literal code entered at signup)
ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by VARCHAR(50);

-- Check and add referral_earnings (defaulting to zero)
ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_earnings DECIMAL(12,2) NOT NULL DEFAULT 0.00;

-- Ensure referral_code type is VARCHAR(50) (widening it from VARCHAR(20))
ALTER TABLE users ALTER COLUMN referral_code TYPE VARCHAR(50);

-- 3. Create referral_configs table
CREATE TABLE IF NOT EXISTS referral_configs (
  id                      UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_code           VARCHAR(50)    UNIQUE NOT NULL,
  user_id                 UUID           REFERENCES users(id) ON DELETE CASCADE,
  division_type           VARCHAR(50)    NOT NULL, -- 'flat_with_expiry_amount', 'flat_with_expiry_date', 'fixed_split'
  reward_value            DECIMAL(12,2),            -- flat reward in KES
  split_percentage_user   DECIMAL(5,2),             -- partner split %
  split_percentage_us     DECIMAL(5,2),             -- our split %
  expiry_amount           DECIMAL(12,2),            -- total earnings cap
  expiry_date             DATE,                     -- date-based expiry
  fixed_split_cap         DECIMAL(12,2),            -- split cap
  is_active               BOOLEAN        DEFAULT true,
  created_at              TIMESTAMPTZ    DEFAULT NOW(),
  updated_at              TIMESTAMPTZ    DEFAULT NOW()
);

-- 4. Create referral_otp_requests table
CREATE TABLE IF NOT EXISTS referral_otp_requests (
  id                  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id      UUID           REFERENCES users(id) ON DELETE CASCADE,
  new_referral_code   VARCHAR(50),
  otp_hash            TEXT           NOT NULL,
  delivery_method     VARCHAR(10),   -- 'email' or 'sms'
  destination         TEXT           NOT NULL, -- email or phone number
  purpose             TEXT           DEFAULT 'referral_code_change',
  config_snapshot     JSONB,         -- snapshot of division config
  expires_at          TIMESTAMPTZ    NOT NULL,
  used                BOOLEAN        DEFAULT false,
  attempts            INTEGER        NOT NULL DEFAULT 0, -- added for rate limiting attempts
  created_at          TIMESTAMPTZ    DEFAULT NOW()
);

-- 5. Create indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code);
CREATE INDEX IF NOT EXISTS idx_users_referred_by ON users(referred_by);
CREATE INDEX IF NOT EXISTS idx_referral_configs_referral_code ON referral_configs(referral_code);
CREATE INDEX IF NOT EXISTS idx_referral_otp_requests_expires_at ON referral_otp_requests(expires_at);
