const express = require('express');
const router = express.Router();
const { logScanAttempt, getScanLogs, getUserScanLogs } = require('../controllers/scanLogController');

router.post('/', logScanAttempt);
router.get('/', getScanLogs);
router.get('/user/:userId', getUserScanLogs);

module.exports = router;
