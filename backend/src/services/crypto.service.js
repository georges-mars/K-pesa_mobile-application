'use strict';

/**
 * crypto.service.js — Field-level AES-256-GCM encryption with rotating DEKs.
 *
 * KEY HIERARCHY
 * ─────────────
 *   Master KEK  (process.env.MASTER_KEY — 32 bytes hex, never in DB)
 *       │
 *       └─ encrypts one DEK per domain (stored in encryption_keys table)
 *               │
 *               └─ encrypts individual data fields
 *
 * DOMAINS
 * ───────
 *   'user_pii'    → users.full_name
 *   'payment'     → payment_methods.phone_number / account_name / account_number
 *   'external'    → users.deriv_access_token / deriv_refresh_token
 *   'payment_hmac'→ HMAC key for searchable phone/account sidecars
 *
 * CIPHERTEXT FORMAT (stored as TEXT in DB)
 * ────────────────────────────────────────
 *   "<iv_hex>:<tag_hex>:<ciphertext_hex>"
 *   Example: "a1b2...(32):<c3d4...(32)>:<e5f6...(N)>"
 *
 * KEY ROTATION
 * ────────────
 *   Each row stores its key_version (INTEGER).
 *   On rotation, encrypt() always uses the NEW active DEK.
 *   decrypt() looks up the exact version that was used to encrypt that row,
 *   so old rows remain readable until re-encrypted by key-rotation.js.
 */

const crypto = require('crypto');
const db     = require('../config/database');

const ALGORITHM = 'aes-256-gcm';
const KEY_BYTES = 32; // 256 bits
const IV_BYTES  = 16; // 128 bits (GCM standard)

// In-process DEK cache: { "domain:version": { dek: Buffer, version: Number } }
// DEKs are evicted from the cache after 5 minutes to limit memory exposure.
const _dekCache   = new Map();
const CACHE_TTL   = 5 * 60 * 1000; // 5 minutes

// ── Master KEK ────────────────────────────────────────────────────────────────

function _getMasterKey() {
  const hex = process.env.MASTER_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error('MASTER_KEY must be a 64-char hex string (32 bytes). Run node key-setup.js first.');
  }
  return Buffer.from(hex, 'hex');
}

// ── DEK encrypt / decrypt (for key management only) ───────────────────────────

/** Encrypt a raw 32-byte DEK Buffer with the master KEK. */
function encryptDek(dekBuf) {
  const kek = _getMasterKey();
  const iv  = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, kek, iv);
  const encrypted = Buffer.concat([cipher.update(dekBuf), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    encrypted_dek: encrypted.toString('hex'),
    dek_iv:        iv.toString('hex'),
    dek_tag:       tag.toString('hex'),
  };
}

/** Decrypt a stored DEK back into its raw 32-byte Buffer. */
function decryptDek(encryptedHex, ivHex, tagHex) {
  const kek      = _getMasterKey();
  const decipher = crypto.createDecipheriv(ALGORITHM, kek, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedHex, 'hex')),
    decipher.final(),
  ]);
}

// ── DEK cache helpers ─────────────────────────────────────────────────────────

function _cacheKey(domain, version) {
  return `${domain}:${version}`;
}

function _cacheSet(domain, version, dek) {
  const key = _cacheKey(domain, version);
  _dekCache.set(key, { dek, version, cachedAt: Date.now() });
}

function _cacheGet(domain, version) {
  const key  = _cacheKey(domain, version);
  const entry = _dekCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.cachedAt > CACHE_TTL) {
    _dekCache.delete(key);
    return null;
  }
  return entry;
}

// ── DEK retrieval from DB ─────────────────────────────────────────────────────

/** Fetch + decrypt the currently active DEK for a domain. */
async function getActiveDek(domain) {
  const { rows } = await db.query(
    `SELECT version, encrypted_dek, dek_iv, dek_tag
     FROM encryption_keys
     WHERE domain = $1 AND is_active = TRUE
     ORDER BY version DESC
     LIMIT 1`,
    [domain],
  );
  if (!rows[0]) {
    throw new Error(
      `No active DEK for domain "${domain}". Run node key-setup.js first.`,
    );
  }
  const { version, encrypted_dek, dek_iv, dek_tag } = rows[0];

  const cached = _cacheGet(domain, version);
  if (cached) return cached;

  const dek = decryptDek(encrypted_dek, dek_iv, dek_tag);
  _cacheSet(domain, version, dek);
  return _cacheGet(domain, version);
}

/** Fetch + decrypt a specific version DEK (used during decryption + rotation). */
async function getDekByVersion(domain, version) {
  const cached = _cacheGet(domain, version);
  if (cached) return cached;

  const { rows } = await db.query(
    `SELECT encrypted_dek, dek_iv, dek_tag
     FROM encryption_keys
     WHERE domain = $1 AND version = $2`,
    [domain, version],
  );
  if (!rows[0]) {
    throw new Error(`DEK not found: domain="${domain}" version=${version}`);
  }
  const dek = decryptDek(rows[0].encrypted_dek, rows[0].dek_iv, rows[0].dek_tag);
  _cacheSet(domain, version, dek);
  return _cacheGet(domain, version);
}

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Encrypt a plaintext string with the active DEK for the given domain.
 *
 * @param {string} domain    - One of: 'user_pii', 'payment', 'external'
 * @param {string|null} plaintext
 * @returns {Promise<{ ciphertext: string|null, keyVersion: number|null }>}
 */
async function encrypt(domain, plaintext) {
  if (plaintext == null || plaintext === '') {
    return { ciphertext: null, keyVersion: null };
  }

  const { dek, version } = await getActiveDek(domain);
  const iv     = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, dek, iv);
  const data   = Buffer.concat([
    cipher.update(Buffer.from(String(plaintext), 'utf8')),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  const ciphertext = [
    iv.toString('hex'),
    tag.toString('hex'),
    data.toString('hex'),
  ].join(':');

  return { ciphertext, keyVersion: version };
}

/**
 * Decrypt a stored ciphertext back to plaintext.
 *
 * @param {string} domain
 * @param {string|null} ciphertext   - "<iv>:<tag>:<data>" hex string
 * @param {number} keyVersion        - which DEK version to use
 * @returns {Promise<string|null>}
 */
async function decrypt(domain, ciphertext, keyVersion) {
  if (!ciphertext) return null;

  const parts = ciphertext.split(':');
  if (parts.length !== 3) {
    throw new Error(`Malformed ciphertext for domain "${domain}"`);
  }
  const [ivHex, tagHex, dataHex] = parts;

  const { dek } = keyVersion != null
    ? await getDekByVersion(domain, keyVersion)
    : await getActiveDek(domain);

  const decipher = crypto.createDecipheriv(ALGORITHM, dek, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  const plain = Buffer.concat([
    decipher.update(Buffer.from(dataHex, 'hex')),
    decipher.final(),
  ]);
  return plain.toString('utf8');
}

/**
 * Compute a deterministic HMAC of a value using the 'payment_hmac' DEK.
 * Used to build searchable sidecars for encrypted fields.
 *
 * @param {string|null} value  - plaintext phone number or account number
 * @returns {Promise<string|null>}  hex HMAC-SHA256 digest
 */
async function hmacField(value) {
  if (!value) return null;
  const { dek } = await getActiveDek('payment_hmac');
  return crypto
    .createHmac('sha256', dek)
    .update(String(value).toLowerCase().trim())
    .digest('hex');
}

module.exports = {
  encrypt,
  decrypt,
  hmacField,
  encryptDek,   // used by key-setup.js and key-rotation.js
  decryptDek,   // used by key-rotation.js
  getActiveDek,
  getDekByVersion,
};
