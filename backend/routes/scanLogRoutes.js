const express = require('express');
const router = express.Router();
const { logScanAttempt, getScanLogs, getUserScanLogs, getOwnerAccessLogs } = require('../controllers/scanLogController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.post('/', logScanAttempt);
router.get('/', getScanLogs);
router.get('/owner-access', getOwnerAccessLogs);
router.get('/user/:userId', getUserScanLogs);

module.exports = router;
