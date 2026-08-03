const express = require('express');
const router = express.Router();
const { getDailyDigest, stageOutboundPackage, generateDispatchLink, batchStageOutboundPackages } = require('../controllers/businessController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.get('/daily-digest', getDailyDigest);
router.post('/outbound-staging', stageOutboundPackage);
router.post('/batch-outbound-staging', batchStageOutboundPackages);
router.post('/generate-dispatch-link', generateDispatchLink);

module.exports = router;
