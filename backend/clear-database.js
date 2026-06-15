/**
 * Clear all data from the K-PESA database
 * Run with: node clear-database.js
 */

const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function clearDatabase() {
  try {
    console.log('⚠️  WARNING: This will DELETE ALL DATA from the database!');
    console.log('Database:', process.env.DB_NAME);
    console.log('');

    // Give user time to cancel (Ctrl+C)
    console.log('Starting in 3 seconds... Press Ctrl+C to cancel');
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log('\n🗑️  Clearing database...\n');

    // Disable foreign key checks
    await pool.query("SET session_replication_role = 'replica'");

    // Truncate all tables
    await pool.query('TRUNCATE TABLE affiliate_redemptions CASCADE');
    console.log('✓ Cleared affiliate_redemptions');

    await pool.query('TRUNCATE TABLE transactions CASCADE');
    console.log('✓ Cleared transactions');

    await pool.query('TRUNCATE TABLE refresh_tokens CASCADE');
    console.log('✓ Cleared refresh_tokens');

    await pool.query('TRUNCATE TABLE otps CASCADE');
    console.log('✓ Cleared otps');

    await pool.query('TRUNCATE TABLE payment_methods CASCADE');
    console.log('✓ Cleared payment_methods');

    await pool.query('TRUNCATE TABLE users CASCADE');
    console.log('✓ Cleared users');

    await pool.query('TRUNCATE TABLE encryption_keys CASCADE');
    console.log('✓ Cleared encryption_keys');

    await pool.query('TRUNCATE TABLE device_biometrics CASCADE');
    console.log('✓ Cleared device_biometrics');

    // Re-enable foreign key checks
    await pool.query("SET session_replication_role = 'origin'");

    // Reset sequences
    await pool.query('ALTER SEQUENCE users_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE payment_methods_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE otps_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE refresh_tokens_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE transactions_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE affiliate_redemptions_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE encryption_keys_id_seq RESTART WITH 1');
    await pool.query('ALTER SEQUENCE device_biometrics_id_seq RESTART WITH 1');

    console.log('✓ Reset ID sequences');

    console.log('\n✅ All data cleared successfully!\n');
    console.log('Next steps:');
    console.log('  1. Run: node key-setup.js (to regenerate encryption keys)');
    console.log('  2. Test signup flow from your Flutter app');

  } catch (error) {
    console.error('❌ Error clearing database:', error.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

clearDatabase();
