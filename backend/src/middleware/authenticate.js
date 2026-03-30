'use strict';

const jwt = require('jsonwebtoken');

/**
 * Middleware: verifies Bearer JWT and attaches req.user = { id, email }.
 * Returns 401 if token is missing or invalid.
 */
function authenticate(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization header missing or malformed.' });
  }

  const token = authHeader.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = { id: payload.sub, email: payload.email };
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Access token expired.', code: 'TOKEN_EXPIRED' });
    }
    return res.status(401).json({ error: 'Invalid access token.' });
  }
}

/**
 * Optional auth: attaches req.user if a valid Bearer token is present,
 * but always calls next() — never returns 401.
 * Use for endpoints that work both authenticated and unauthenticated.
 */
function optionalAuthenticate(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (authHeader && authHeader.startsWith('Bearer ')) {
    try {
      const payload = jwt.verify(authHeader.slice(7), process.env.JWT_SECRET);
      req.user = { id: payload.sub, email: payload.email };
    } catch (_) { /* ignore invalid/expired token */ }
  }
  next();
}

module.exports = authenticate;
module.exports.optional = optionalAuthenticate;
