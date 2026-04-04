const express = require('express');
const router = express.Router();
const { createNotification, getUserNotifications, markAsRead, markAllAsRead } = require('../controllers/notificationController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.post('/', createNotification);
router.get('/user/:userId', getUserNotifications);
router.patch('/:id/read', markAsRead);
router.patch('/user/:userId/read', markAllAsRead);

module.exports = router;
