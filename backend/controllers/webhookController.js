const Task = require('../models/Task');
const User = require('../models/User');

/**
 * POST /api/webhooks/shopee
 * Receives ORDER_CREATED / MESSAGE_RECEIVED callbacks from Shopee Open Platform
 */
exports.handleShopeeWebhook = async (req, res) => {
  try {
    console.log('🛍️ Shopee Webhook Received:', JSON.stringify(req.body));
    const { order_sn, buyer_username, item_list, tracking_no, courier_name } = req.body;

    const owner = await User.findOne({ role: 'admin' });
    const userId = owner ? owner._id.toString() : 'shopee_auto_sync';

    const itemNames = (item_list || []).map(i => i.item_name).join(', ') || 'Shopee Order';

    const task = await Task.create({
      userId,
      title: `Shopee Order #${order_sn || Math.floor(1000 + Math.random() * 9000)}: ${itemNames}`,
      stage: 'CRAFTING',
      platform: 'SHOPEE',
      customerName: buyer_username || 'Shopee Buyer',
      trackingId: tracking_no || `SPX-${order_sn || Date.now()}`,
      courierName: courier_name || 'Spx',
      notes: 'Auto-synced from Shopee Open Platform'
    });

    const io = req.app.get('io');
    if (io) io.emit('taskUpdate', task);

    res.json({ success: true, message: 'Shopee webhook processed', data: task });
  } catch (err) {
    console.error('❌ handleShopeeWebhook error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/webhooks/tiktok
 * Receives order notifications from TikTok Shop Partner API
 */
exports.handleTikTokWebhook = async (req, res) => {
  try {
    console.log('🎵 TikTok Shop Webhook Received:', JSON.stringify(req.body));
    const { order_id, buyer_name, product_name, tracking_number } = req.body;

    const owner = await User.findOne({ role: 'admin' });
    const userId = owner ? owner._id.toString() : 'tiktok_auto_sync';

    const task = await Task.create({
      userId,
      title: `TikTok Order #${order_id || Math.floor(1000 + Math.random() * 9000)}: ${product_name || 'Craft Product'}`,
      stage: 'CRAFTING',
      platform: 'TIKTOK',
      customerName: buyer_name || 'TikTok Customer',
      trackingId: tracking_number || `TT-${order_id || Date.now()}`,
      courierName: 'J&T Express',
      notes: 'Auto-synced from TikTok Shop Partner API'
    });

    const io = req.app.get('io');
    if (io) io.emit('taskUpdate', task);

    res.json({ success: true, message: 'TikTok webhook processed', data: task });
  } catch (err) {
    console.error('❌ handleTikTokWebhook error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/webhooks/instagram
 * Receives DM lead events from Meta Graph API
 */
exports.handleInstagramWebhook = async (req, res) => {
  try {
    console.log('📸 Instagram Webhook Received:', JSON.stringify(req.body));
    const { sender_name, message_text, phone } = req.body;

    const owner = await User.findOne({ role: 'admin' });
    const userId = owner ? owner._id.toString() : 'ig_auto_sync';

    const task = await Task.create({
      userId,
      title: `IG Lead: ${message_text || 'Custom Craft Inquiry'}`,
      stage: 'INQUIRY',
      platform: 'INSTAGRAM',
      customerName: sender_name || 'IG Customer',
      customerPhone: phone || '',
      notes: 'Auto-synced from Instagram DM via Meta Graph API'
    });

    const io = req.app.get('io');
    if (io) io.emit('taskUpdate', task);

    res.json({ success: true, message: 'Instagram webhook processed', data: task });
  } catch (err) {
    console.error('❌ handleInstagramWebhook error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};
