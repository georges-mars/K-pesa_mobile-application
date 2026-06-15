'use strict';

function resolveDbSsl() {
  const sslMode = (process.env.DB_SSL || '').toLowerCase();
  if (!['true', '1', 'require'].includes(sslMode)) return false;

  const rejectUnauthorized =
    (process.env.DB_SSL_REJECT_UNAUTHORIZED || 'false').toLowerCase() === 'true';

  return { rejectUnauthorized };
}

module.exports = resolveDbSsl;
