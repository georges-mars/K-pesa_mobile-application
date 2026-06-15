'use strict';

/**
 * migrate.js — runs all SQL migration files in order.
 * Usage: node migrate.js
 *
 * Each file is run only once; a simple migrations_run table tracks what has been applied.
 */
require('dotenv').config();
const { Pool } = require('pg');
const fs   = require('fs');
const path = require('path');
const resolveDbSsl = require('./src/config/db-ssl');

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: resolveDbSsl(),
});

async function migrate() {
  const client = await pool.connect();
  try {
    // Create tracking table if it doesn't exist
    await client.query(`
      CREATE TABLE IF NOT EXISTS migrations_run (
        filename   VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const migrationsDir = path.join(__dirname, 'migrations');
    const files = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      const { rows } = await client.query(
        'SELECT filename FROM migrations_run WHERE filename = $1',
        [file],
      );
      if (rows.length > 0) {
        console.log(`  skip  ${file} (already applied)`);
        continue;
      }

      console.log(`  run   ${file}`);
      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
      await client.query('BEGIN');
      await client.query(sql);
      await client.query(
        'INSERT INTO migrations_run (filename) VALUES ($1)',
        [file],
      );
      await client.query('COMMIT');
      console.log(`  done  ${file}`);
    }

    console.log('\nAll migrations applied successfully.');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
