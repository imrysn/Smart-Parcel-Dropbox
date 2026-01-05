const express = require('express');
const router = express.Router();
const { sendCommand, getLatestCommand } = require('../controllers/deviceController');

router.post('/', sendCommand);
router.get('/', getLatestCommand);
router.get('/latest', getLatestCommand);

module.exports = router;
