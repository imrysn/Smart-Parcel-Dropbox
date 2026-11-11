const express = require('express');
const router = express.Router();
const { authenticateDeviceHttp } = require('../utils/deviceSessions');
const {
  initToken,
  verifyBarcode,
  syncActiveBarcodes
} = require('../controllers/hardwareController');

router.get('/init-token', authenticateDeviceHttp, initToken);
router.post('/verify-barcode', authenticateDeviceHttp, verifyBarcode);
router.get('/sync-active-barcodes/:deviceId', authenticateDeviceHttp, syncActiveBarcodes);

module.exports = router;
