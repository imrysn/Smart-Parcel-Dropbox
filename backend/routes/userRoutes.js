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

const { authMiddleware } = require('../utils/auth');

// Authentication routes (Public)
router.post('/register', registerUser);
router.post('/login', loginUser);

// Password reset routes (Public)
router.post('/request-reset', requestPasswordReset);
router.post('/verify-reset-code', verifyResetCode);
router.post('/reset-password', resetPassword);

// Public check-email
router.get('/check-email/:email', checkUserByEmail);

// User management routes (Protected)
router.use(authMiddleware);

router.get('/', getAllUsers);
router.get('/:id', getUserProfile);
router.patch('/:id', updateUser);
router.delete('/:id', deleteUser);

module.exports = router;
