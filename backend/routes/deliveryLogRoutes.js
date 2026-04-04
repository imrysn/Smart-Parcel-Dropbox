const express = require('express');
const router = express.Router();
const { getDeliveryLogs, addDeliveryLog, getAllDeliveryLogs } = require('../controllers/deliveryLogController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.get('/', getAllDeliveryLogs);
router.get('/:trackingId', getDeliveryLogs);
router.post('/', addDeliveryLog);

module.exports = router;
