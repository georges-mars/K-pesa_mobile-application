'use strict';

const biometricService = require('../services/biometric.service');

const clientIp = (req) => req.headers['x-forwarded-for']?.split(',')[0] || req.socket.remoteAddress;

/**
 * POST /api/v1/auth/biometric/enroll
 * Requires JWT auth. Body: { deviceId, deviceName? }
 */
async function enroll(req, res, next) {
  try {
    const { deviceId, deviceName } = req.body;
    const result = await biometricService.enrollDevice(req.user.id, deviceId, deviceName);
    res.status(201).json({ message: 'Device enrolled for biometric login.', id: result.id });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/v1/auth/biometric/login
 * No auth required. Body: { deviceId }
 */
async function loginBiometric(req, res, next) {
  try {
    const { deviceId } = req.body;
    const result = await biometricService.loginByDevice(deviceId, clientIp(req));
    res.json(result);
  } catch (err) {
    next(err);
  }
}

/**
 * DELETE /api/v1/auth/biometric/remove
 * Requires JWT auth. Body: { deviceId }
 */
async function remove(req, res, next) {
  try {
    const { deviceId } = req.body;
    await biometricService.removeDevice(req.user.id, deviceId);
    res.json({ message: 'Device removed from biometric login.' });
  } catch (err) {
    next(err);
  }
}

module.exports = { enroll, loginBiometric, remove };
