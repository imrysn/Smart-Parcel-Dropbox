const express = require('express');
const router = express.Router();
const {
  initToken,
  verifyBarcode,
  syncActiveBarcodes
} = require('../controllers/hardwareController');

// Public endpoints called by ESP32 hardware
router.get('/init-token', initToken);
router.post('/verify-barcode', verifyBarcode);
router.get('/sync-active-barcodes/:deviceId', syncActiveBarcodes);

module.exports = router;
