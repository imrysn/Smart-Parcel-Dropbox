const express = require('express');
const router = express.Router();
const { handleShopeeWebhook, handleTikTokWebhook, handleInstagramWebhook } = require('../controllers/webhookController');

router.post('/shopee', handleShopeeWebhook);
router.post('/tiktok', handleTikTokWebhook);
router.post('/instagram', handleInstagramWebhook);

module.exports = router;
