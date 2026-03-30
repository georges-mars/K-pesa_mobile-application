-- Migration 009: add display_name column to users
--
-- Separate from full_name (which comes from registration).
-- display_name is set ONLY via the "What name should we call you?" popup
-- or auto-filled from deriv_name when Deriv is connected.
-- NULL = user has not yet set a display name → app shows the prompt.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS display_name TEXT;
