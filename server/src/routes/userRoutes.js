const express = require('express');
const router = express.Router();
const {
    registerUser,
    loginUser,
    getUserProfile,
    getAllUsers,
    updateUser,
    deleteUser,
    checkUserByEmail,
    requestPasswordReset,
    verifyResetCode,
    resetPassword
} = require('../controllers/userController');

// Authentication routes
router.post('/register', registerUser);
router.post('/login', loginUser);

// Password reset routes
router.post('/request-reset', requestPasswordReset);
router.post('/verify-reset-code', verifyResetCode);
router.post('/reset-password', resetPassword);

// User management routes
router.get('/', getAllUsers);
router.get('/check-email/:email', checkUserByEmail);
router.get('/:id', getUserProfile);
router.patch('/:id', updateUser);
router.delete('/:id', deleteUser);

module.exports = router;
