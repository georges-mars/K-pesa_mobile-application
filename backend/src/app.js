'use strict';

const express = require('express');
const helmet  = require('helmet');
const cors    = require('cors');

const { generalLimiter } = require('./middleware/rateLimiter');
const errorHandler        = require('./middleware/errorHandler');
const logger              = require('./config/logger');

const authRoutes     = require('./routes/auth.routes');
const otpRoutes      = require('./routes/otp.routes');
const userRoutes     = require('./routes/user.routes');
const depositRoutes  = require('./routes/deposit.routes');
const withdrawRoutes = require('./routes/withdraw.routes');
const derivRoutes    = require('./routes/deriv.routes');
const callbackRoutes  = require('./routes/callback.routes');
const biometricRoutes = require('./routes/biometric.routes');

const app = express();

// ── Security headers ──────────────────────────────────────────────────────────
app.use(helmet());

// ── CORS — allow requests from the Flutter app (any origin in dev) ────────────
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',')
    : '*',
  methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Body parsing ──────────────────────────────────────────────────────────────
app.use(express.json({ limit: '50kb' }));

// ── Request logging (dev) ─────────────────────────────────────────────────────
if (process.env.NODE_ENV !== 'test') {
  app.use((req, _res, next) => {
    logger.debug(`${req.method} ${req.path}`);
    next();
  });
}

// ── Global rate limit ─────────────────────────────────────────────────────────
app.use(generalLimiter);

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', ts: new Date().toISOString() }));

// ── API routes ────────────────────────────────────────────────────────────────
const BASE = '/api/v1';

app.use(`${BASE}/auth`,      authRoutes);
app.use(`${BASE}/otp`,       otpRoutes);
app.use(`${BASE}/user`,      userRoutes);
app.use(`${BASE}/deposit`,   depositRoutes);
app.use(`${BASE}/withdraw`,  withdrawRoutes);
app.use(`${BASE}/deriv`,     derivRoutes);
app.use(`${BASE}/callbacks`, callbackRoutes);
app.use(`${BASE}/auth/biometric`, biometricRoutes);

// ── 404 catch-all ─────────────────────────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// ── Global error handler ──────────────────────────────────────────────────────
app.use(errorHandler);

module.exports = app;
