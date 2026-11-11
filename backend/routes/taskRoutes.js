const express = require('express');
const router = express.Router();
const { getTasks, createTask, updateTaskStage, deleteTask } = require('../controllers/taskController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.get('/', getTasks);
router.post('/', createTask);
router.patch('/:id/stage', updateTaskStage);
router.delete('/:id', deleteTask);

module.exports = router;
