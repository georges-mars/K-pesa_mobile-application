'use strict';

const KENYAN_MOBILE_PATTERN = /^(\+254|0)?[17]\d{8}$/;

function normalizeKenyanPhone(phone) {
  const cleaned = String(phone || '').trim().replace(/[\s-]/g, '');
  if (!KENYAN_MOBILE_PATTERN.test(cleaned)) {
    const err = new Error(
      'Phone must be a valid Kenyan mobile number (e.g. 07XXXXXXXX, 01XXXXXXXX, or +254XXXXXXXXX).',
    );
    err.type = 'VALIDATION';
    throw err;
  }

  if (cleaned.startsWith('+254')) return cleaned;
  if (cleaned.startsWith('0')) return `+254${cleaned.slice(1)}`;
  return `+254${cleaned}`;
}

module.exports = {
  KENYAN_MOBILE_PATTERN,
  normalizeKenyanPhone,
};
