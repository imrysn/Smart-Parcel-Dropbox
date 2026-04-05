const express = require('express');
const router = express.Router();
const { registerTracking, getUserTracking, getAllTracking, getTrackingById, updateTrackingStatus, resetTracking, simulateTracking, deleteTracking } = require('../controllers/trackingController');
const { authMiddleware } = require('../utils/auth');

// All routes here should be protected
router.use(authMiddleware);

router.post('/', registerTracking);
router.get('/', getAllTracking);
router.get('/user/:userId', getUserTracking);
router.get('/:trackingId', getTrackingById);
router.delete('/:trackingId', deleteTracking);
router.patch('/:trackingId/status', updateTrackingStatus);
router.post('/:trackingId/reset', resetTracking);
router.post('/:trackingId/simulate', simulateTracking);

module.exports = router;
