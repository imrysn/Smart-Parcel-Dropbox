const express = require('express');
const router = express.Router();
const { logScanAttempt, getScanLogs, getUserScanLogs, getOwnerAccessLogs } = require('../controllers/scanLogController');

router.post('/', logScanAttempt);
router.get('/', getScanLogs);
router.get('/owner-access', getOwnerAccessLogs); // Must be before /user/:userId to not match as a params ID
router.get('/user/:userId', getUserScanLogs);

module.exports = router;
