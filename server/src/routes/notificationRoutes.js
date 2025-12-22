const express = require('express');
const router = express.Router();
const { createNotification, getUserNotifications, markAsRead, markAllAsRead } = require('../controllers/notificationController');

router.post('/', createNotification);
router.get('/user/:userId', getUserNotifications);
router.patch('/:id/read', markAsRead);
router.patch('/user/:userId/read', markAllAsRead);

module.exports = router;
