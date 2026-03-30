'use strict';

/**
 * Returns an Express middleware that validates req.body against a Joi schema.
 * On failure: 400 with the first validation error message.
 */
function validate(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, {
      abortEarly: true,
      stripUnknown: true,
    });
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    req.body = value; // replace with stripped/coerced value
    next();
  };
}

module.exports = validate;
