const express = require('express');
const router = express.Router();
const { registerTracking, getUserTracking, getAllTracking, getTrackingById, updateTrackingStatus } = require('../controllers/trackingController');

router.post('/', registerTracking);
router.get('/', getAllTracking);
router.get('/:trackingId', getTrackingById);
router.get('/user/:userId', getUserTracking);
router.patch('/:trackingId/status', updateTrackingStatus);

module.exports = router;
