'use strict';

const logger = require('../config/logger');

// Known app-level error types that map to specific HTTP codes
const ERROR_MAP = {
  CONFLICT:            409,
  NOT_FOUND:           404,
  FORBIDDEN:           403,
  UNAUTHORIZED:        401,
  VALIDATION:          400,
  RATE_LIMIT:          429,
  SERVICE_UNAVAILABLE: 503,
};

/**
 * Global Express error handler.
 * All errors thrown with err.type from ERROR_MAP are mapped to the correct code.
 * All others → 500.
 */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
  const status = ERROR_MAP[err.type] || 500;

  if (status === 500) {
    logger.error('Unhandled error', {
      path: req.path,
      method: req.method,
      error: err.message,
      stack: err.stack,
    });
  } else {
    logger.warn('App error', { path: req.path, type: err.type, message: err.message });
  }

  res.status(status).json({
    error: status === 500 ? 'Internal server error.' : err.message,
  });
}

// Helper: create a typed app error
function createError(type, message) {
  const err = new Error(message);
  err.type = type;
  return err;
}

module.exports = errorHandler;
module.exports.createError = createError;
