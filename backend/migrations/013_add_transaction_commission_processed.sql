-- Migration 013: Add commission_processed flag to transactions
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS commission_processed BOOLEAN NOT NULL DEFAULT FALSE;
