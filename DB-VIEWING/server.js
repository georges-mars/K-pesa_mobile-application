'use strict';

const path = require('path');
const express = require('express');
const { Pool } = require('pg');
const dotenv = require('dotenv');

dotenv.config();
dotenv.config({ path: path.join(__dirname, '..', 'backend', '.env') });

const app = express();
const PORT = Number(process.env.DB_VIEWER_PORT || 5050);

const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED === 'true' } : false,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

const TABLE_NAME_RX = /^[a-zA-Z_][a-zA-Z0-9_]*$/;

function assertIdentifier(name, kind = 'identifier') {
  if (!TABLE_NAME_RX.test(name)) {
    const err = new Error(`Invalid ${kind}`);
    err.status = 400;
    throw err;
  }
}

function quoteIdentifier(name) {
  assertIdentifier(name);
  return `"${name}"`;
}

async function listPublicTables() {
  const { rows } = await pool.query(
    `SELECT
       t.tablename AS table_name,
       COALESCE(s.n_live_tup, 0)::bigint AS estimated_rows
     FROM pg_catalog.pg_tables t
     LEFT JOIN pg_stat_user_tables s
       ON s.schemaname = t.schemaname
      AND s.relname = t.tablename
     WHERE t.schemaname = 'public'
     ORDER BY t.tablename ASC`,
  );
  return rows;
}

app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/health', async (_req, res, next) => {
  try {
    const ping = await pool.query('SELECT NOW() AS now');
    res.json({
      ok: true,
      connected: true,
      time: ping.rows[0].now,
      database: process.env.DB_NAME,
      host: process.env.DB_HOST,
    });
  } catch (err) {
    next(err);
  }
});

app.get('/api/tables', async (_req, res, next) => {
  try {
    const tables = await listPublicTables();
    res.json({ tables });
  } catch (err) {
    next(err);
  }
});

app.get('/api/tables/:table/meta', async (req, res, next) => {
  try {
    const table = req.params.table;
    assertIdentifier(table, 'table name');

    const tables = await listPublicTables();
    const exists = tables.some((t) => t.table_name === table);
    if (!exists) return res.status(404).json({ error: 'Table not found' });

    const { rows: columns } = await pool.query(
      `SELECT
         column_name,
         data_type,
         is_nullable,
         column_default
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = $1
       ORDER BY ordinal_position ASC`,
      [table],
    );

    const safeTable = quoteIdentifier(table);
    const countResult = await pool.query(`SELECT COUNT(*)::bigint AS total_rows FROM ${safeTable}`);

    res.json({
      table,
      totalRows: Number(countResult.rows[0].total_rows),
      columns,
    });
  } catch (err) {
    next(err);
  }
});

app.get('/api/tables/:table/rows', async (req, res, next) => {
  try {
    const table = req.params.table;
    assertIdentifier(table, 'table name');

    const limit = Math.min(Math.max(Number(req.query.limit || 50), 1), 200);
    const offset = Math.max(Number(req.query.offset || 0), 0);
    const orderBy = req.query.orderBy ? String(req.query.orderBy) : null;
    const orderDir = String(req.query.orderDir || 'desc').toLowerCase() === 'asc' ? 'ASC' : 'DESC';

    const tables = await listPublicTables();
    const exists = tables.some((t) => t.table_name === table);
    if (!exists) return res.status(404).json({ error: 'Table not found' });

    const { rows: columns } = await pool.query(
      `SELECT column_name
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = $1
       ORDER BY ordinal_position ASC`,
      [table],
    );
    const columnNames = columns.map((c) => c.column_name);

    if (orderBy) assertIdentifier(orderBy, 'orderBy column');

    let selectedOrderBy = orderBy && columnNames.includes(orderBy) ? orderBy : null;
    if (!selectedOrderBy) {
      if (columnNames.includes('updated_at')) selectedOrderBy = 'updated_at';
      else if (columnNames.includes('created_at')) selectedOrderBy = 'created_at';
      else if (columnNames.includes('id')) selectedOrderBy = 'id';
      else selectedOrderBy = columnNames[0];
    }

    const safeTable = quoteIdentifier(table);
    const safeOrderBy = quoteIdentifier(selectedOrderBy);
    const sql = `SELECT * FROM ${safeTable} ORDER BY ${safeOrderBy} ${orderDir} LIMIT $1 OFFSET $2`;
    const { rows } = await pool.query(sql, [limit, offset]);

    res.json({
      table,
      limit,
      offset,
      orderBy: selectedOrderBy,
      orderDir: orderDir.toLowerCase(),
      columns: columnNames,
      rows,
    });
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  const status = err.status || 500;
  res.status(status).json({
    error: status === 500 ? 'Internal server error' : err.message,
  });
});

app.listen(PORT, () => {
  console.log(`DB viewer running at http://localhost:${PORT}`);
});
