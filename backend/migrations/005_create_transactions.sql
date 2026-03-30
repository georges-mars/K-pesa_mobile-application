-- Migration 005: transactions table
CREATE TABLE IF NOT EXISTS transactions (
  id                         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID           NOT NULL REFERENCES users(id),
  type                       VARCHAR(20)    NOT NULL CHECK (type IN ('deposit', 'withdrawal')),
  status                     VARCHAR(30)    NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),

  -- Amounts
  amount_kes                 NUMERIC(12, 2) NOT NULL,
  amount_usd                 NUMERIC(12, 4),
  exchange_rate              NUMERIC(12, 5),

  -- M-Pesa STK Push (deposits)
  mpesa_checkout_request_id  VARCHAR(100),  -- from Daraja STK Push response
  mpesa_transaction_id       VARCHAR(50),   -- MpesaReceiptNumber from callback
  mpesa_phone                VARCHAR(20),   -- E.164 recipient/sender

  -- M-Pesa B2C (withdrawals)
  b2c_conversation_id        VARCHAR(100),  -- from Daraja B2C response
  b2c_originator_id          VARCHAR(100),  -- our transactionId used as correlation key
  b2c_transaction_id         VARCHAR(50),   -- TransactionReceipt from callback

  -- Destination (for deposits)
  destination_type           VARCHAR(20)
    CHECK (destination_type IN ('deriv', 'mt5', 'binance')),
  destination_account        VARCHAR(50),

  -- Failure details
  failure_reason             TEXT,
  callback_payload           JSONB,         -- raw Safaricom payload (for audit/debug)

  created_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_txn_user_id     ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_txn_status      ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_txn_stk_id      ON transactions(mpesa_checkout_request_id)
  WHERE mpesa_checkout_request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_txn_b2c_conv_id ON transactions(b2c_conversation_id)
  WHERE b2c_conversation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_txn_created_at  ON transactions(created_at DESC);
