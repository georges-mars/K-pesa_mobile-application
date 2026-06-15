'use strict';

const userService  = require('../services/user.service');
const derivService = require('../services/deriv.service');
const logger       = require('../config/logger');

async function getProfile(req, res, next) {
  try {
    const profile = await userService.getProfile(req.user.id);
    res.json(profile);
  } catch (err) { next(err); }
}

async function updateProfile(req, res, next) {
  try {
    const updated = await userService.updateProfile(req.user.id, req.body);
    res.json(updated);
  } catch (err) { next(err); }
}

async function listPaymentMethods(req, res, next) {
  try {
    const methods = await userService.listPaymentMethods(req.user.id);
    res.json({ paymentMethods: methods });
  } catch (err) { next(err); }
}

async function addPaymentMethod(req, res, next) {
  try {
    const method = await userService.addPaymentMethod(req.user.id, req.body);
    res.status(201).json(method);
  } catch (err) { next(err); }
}

async function deletePaymentMethod(req, res, next) {
  try {
    await userService.deletePaymentMethod(req.user.id, req.params.id);
    res.json({ message: 'Payment method removed.' });
  } catch (err) { next(err); }
}

async function setDefaultPaymentMethod(req, res, next) {
  try {
    await userService.setDefaultPaymentMethod(req.user.id, req.params.id);
    res.json({ message: 'Default payment method updated.' });
  } catch (err) { next(err); }
}

async function getBalances(req, res, next) {
  try {
    const balances = await derivService.getBalances(req.user.id);
    res.json({
      ...balances,
      appConfig: {
        minDepositUsd: Number(process.env.MIN_DEPOSIT_USD || 5),
      },
    });
  } catch (err) { next(err); }
}

async function listTransactions(req, res, next) {
  try {
    const { page, limit, type, status } = req.query;
    const result = await userService.listTransactions(req.user.id, {
      page:   parseInt(page  || '1'),
      limit:  parseInt(limit || '20'),
      type,
      status,
    });
    res.json(result);
  } catch (err) { next(err); }
}

async function verifyPassword(req, res, next) {
  try {
    const { password } = req.body;
    const isValid = await userService.verifyPassword(req.user.id, password);
    if (!isValid) {
      return res.status(400).json({ error: 'Incorrect current password.' });
    }
    res.json({ message: 'Password verified successfully.' });
  } catch (err) { next(err); }
}

async function changePassword(req, res, next) {
  try {
    const { verificationToken, newPassword } = req.body;
    await userService.changePassword(req.user.id, verificationToken, newPassword);
    res.json({ message: 'Password changed successfully.' });
  } catch (err) { next(err); }
}

async function getEarnings(req, res, next) {
  try {
    const earningsData = await userService.getEarnings(req.user.id);
    res.json(earningsData);
  } catch (err) { next(err); }
}

async function getReferralProfile(req, res, next) {
  try {
    const data = await userService.getReferralProfile(req.user.id);
    res.json(data);
  } catch (err) { next(err); }
}

module.exports = {
  getProfile,
  updateProfile,
  listPaymentMethods,
  addPaymentMethod,
  deletePaymentMethod,
  setDefaultPaymentMethod,
  getBalances,
  listTransactions,
  verifyPassword,
  changePassword,
  getEarnings,
  getReferralProfile,
};
