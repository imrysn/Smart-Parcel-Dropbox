const express = require('express');
const router = express.Router();
const { registerUser, getUserProfile, getAllUsers, updateUser, deleteUser } = require('../controllers/userController');

router.post('/', registerUser);
router.get('/', getAllUsers);
router.get('/:uid', getUserProfile);
router.patch('/:uid', updateUser);
router.delete('/:uid', deleteUser);

module.exports = router;
