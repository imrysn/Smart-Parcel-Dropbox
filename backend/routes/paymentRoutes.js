const express = require('express');
const router = express.Router();
const { getPaymentConfig, savePaymentConfig, generateInvoice } = require('../controllers/paymentController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.get('/config', getPaymentConfig);
router.post('/config', savePaymentConfig);
router.post('/generate-invoice', generateInvoice);

module.exports = router;
