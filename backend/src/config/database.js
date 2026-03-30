'use strict';

const { Pool } = require('pg');
const logger = require('./logger');

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max:      20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => {
  logger.error('Idle postgres client error', { error: err.message });
});

// Convenience: run a query with automatic client release
async function query(text, params) {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;
    if (process.env.NODE_ENV !== 'production') {
      logger.debug('DB query', { text: text.slice(0, 80), duration, rows: result.rowCount });
    }
    return result;
  } catch (err) {
    logger.error('DB query error', { text: text.slice(0, 80), error: err.message });
    throw err;
  }
}

// For transactions (BEGIN/COMMIT/ROLLBACK)
async function getClient() {
  return pool.connect();
}

module.exports = { query, getClient, pool };
