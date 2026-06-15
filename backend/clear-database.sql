-- Clear all data from K-PESA database
-- Run with: psql -U kpesa_user -d kpesa -f clear-database.sql
-- Or from psql: \i clear-database.sql

-- Disable foreign key checks temporarily
SET session_replication_role = 'replica';

-- Truncate all tables (fastest method)
TRUNCATE TABLE affiliate_redemptions CASCADE;
TRUNCATE TABLE transactions CASCADE;
TRUNCATE TABLE refresh_tokens CASCADE;
TRUNCATE TABLE otps CASCADE;
TRUNCATE TABLE payment_methods CASCADE;
TRUNCATE TABLE users CASCADE;
TRUNCATE TABLE encryption_keys CASCADE;
TRUNCATE TABLE device_biometrics CASCADE;

-- Re-enable foreign key checks
SET session_replication_role = 'origin';

-- Reset sequences (so IDs start from 1 again)
ALTER SEQUENCE users_id_seq RESTART WITH 1;
ALTER SEQUENCE payment_methods_id_seq RESTART WITH 1;
ALTER SEQUENCE otps_id_seq RESTART WITH 1;
ALTER SEQUENCE refresh_tokens_id_seq RESTART WITH 1;
ALTER SEQUENCE transactions_id_seq RESTART WITH 1;
ALTER SEQUENCE affiliate_redemptions_id_seq RESTART WITH 1;
ALTER SEQUENCE encryption_keys_id_seq RESTART WITH 1;
ALTER SEQUENCE device_biometrics_id_seq RESTART WITH 1;


-- Show confirmation
SELECT 'All data cleared successfully!' AS result;
