const express = require('express');
const router = express.Router();
const {
    registerUser,
    loginUser,
    getMe,
    getUserProfile,
    updateUser,
    changePassword,
    deleteUser,
    requestPasswordReset,
    verifyResetCode,
    resetPassword
} = require('../controllers/userController');

const { authMiddleware } = require('../utils/auth');

// Authentication routes (Public)
router.post('/register', registerUser);
router.post('/login', loginUser);

// Password reset routes (Public)
router.post('/request-reset', requestPasswordReset);
router.post('/verify-reset-code', verifyResetCode);
router.post('/reset-password', resetPassword);

// Protected self-service user routes
router.use(authMiddleware);

router.get('/me', getMe);
router.post('/change-password', changePassword);
router.get('/:id', getUserProfile);
router.patch('/:id', updateUser);
router.delete('/:id', deleteUser);

module.exports = router;
