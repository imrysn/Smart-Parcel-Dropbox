const express = require('express');
const router = express.Router();
const { registerTracking, getUserTracking, getAllTracking, getTrackingById, updateTrackingStatus, resetTracking } = require('../controllers/trackingController');

router.post('/', registerTracking);
router.get('/', getAllTracking);
router.get('/:trackingId', getTrackingById);
router.get('/user/:userId', getUserTracking);
router.patch('/:trackingId/status', updateTrackingStatus);
router.post('/:trackingId/reset', resetTracking); // DEV/TESTING: reset to pending

module.exports = router;
