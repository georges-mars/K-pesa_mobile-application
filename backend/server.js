'use strict';

require('dotenv').config();
const { validateEnv } = require('./src/config/env');
validateEnv();

const app = require('./src/app');
const logger = require('./src/config/logger');

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  logger.info(`K-Pesa API running on port ${PORT} [${process.env.NODE_ENV || 'development'}]`);
});
