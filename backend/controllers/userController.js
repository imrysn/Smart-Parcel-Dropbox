const crypto = require('crypto');
const User = require('../models/User');
const Dropbox = require('../models/Dropbox');
const Tracking = require('../models/Tracking');
const Rider = require('../models/Rider');
const { sendResetCode } = require('../utils/emailService');
const { generateToken } = require('../utils/auth');
const { deviceRoom } = require('../utils/deviceSessions');
const bcrypt = require('bcryptjs');

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RESET_MAX_ATTEMPTS = 5;
const RESET_COOLDOWN_MS = 60 * 1000;

function normalizeEmail(raw) {
    if (typeof raw !== 'string') return null;
    const trimmed = raw.trim().toLowerCase();
    return EMAIL_REGEX.test(trimmed) ? trimmed : null;
}

function sanitizeUserResponse(user) {
    return {
        id: user._id,
        email: user.email,
        fullName: user.fullName || '',
        phoneNumber: user.phoneNumber || '',
        address: user.address || '',
        role: user.role || 'user'
    };
}

// @desc    Register a new user
// @route   POST /api/users/register
exports.registerUser = async (req, res) => {
    try {
        const email = normalizeEmail(req.body?.email);
        const password = typeof req.body?.password === 'string' ? req.body.password : '';
        const fullName = typeof req.body?.fullName === 'string' ? req.body.fullName.trim() : '';
        const phoneNumber = typeof req.body?.phoneNumber === 'string' ? req.body.phoneNumber.trim() : '';
        const address = typeof req.body?.address === 'string' ? req.body.address.trim() : '';

        if (!email) {
            return res.status(400).json({ message: 'Please provide a valid email address' });
        }
        if (password.length < 6) {
            return res.status(400).json({ message: 'Password must be at least 6 characters' });
        }

        console.log(`[USER_CONTROLLER] Registering user: ${email}`);

        const existing = await User.findOne({ email });
        if (existing) {
            console.log(`[USER_CONTROLLER] User already exists: ${email}`);
            return res.status(400).json({ message: 'User already exists' });
        }

        const hashedPassword = await bcrypt.hash(password, 10);

        const user = await User.create({
            email,
            password: hashedPassword,
            fullName,
            phoneNumber,
            address,
            role: 'user'
        });

        const token = generateToken(user._id);

        res.status(201).json({
            message: 'User registered successfully',
            token,
            user: sanitizeUserResponse(user)
        });
    } catch (error) {
        console.error('[USER_CONTROLLER] Registration error:', error);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Login user
// @route   POST /api/users/login
exports.loginUser = async (req, res) => {
    try {
        const email = normalizeEmail(req.body?.email);
        const password = typeof req.body?.password === 'string' ? req.body.password : '';

        if (!email || !password) {
            return res.status(400).json({ message: 'Email and password are required' });
        }

        console.log(`[USER_CONTROLLER] Login attempt: ${email}`);

        const user = await User.findOne({ email });
        if (!user) {
            return res.status(401).json({ message: 'Invalid email or password' });
        }

        const isPasswordValid = await bcrypt.compare(password, user.password);
        if (!isPasswordValid) {
            return res.status(401).json({ message: 'Invalid email or password' });
        }

        const token = generateToken(user._id);

        console.log(`[USER_CONTROLLER] Login successful: ${user.email}`);
        res.json({
            message: 'Login successful',
            token,
            user: sanitizeUserResponse(user)
        });
    } catch (error) {
        console.error('[USER_CONTROLLER] Login error:', error);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get current authenticated user profile
// @route   GET /api/users/me
exports.getMe = async (req, res) => {
    try {
        const user = await User.findById(req.userId).select('-password -resetCode -resetCodeExpiry');
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }
        res.json(user);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get user profile
// @route   GET /api/users/:id
exports.getUserProfile = async (req, res) => {
    try {
        const userId = req.params.id;

        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot access another user\'s profile' });
        }

        const user = await User.findById(userId).select('-password -resetCode -resetCodeExpiry');
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }
        res.json(user);
    } catch (error) {
        console.error(`[USER_CONTROLLER] Error fetching profile: ${error.message}`);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Update user profile
// @route   PATCH /api/users/:id
exports.updateUser = async (req, res) => {
    try {
        const userId = req.params.id;

        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot update another user\'s profile' });
        }

        const updateData = {};
        if (typeof req.body?.fullName === 'string') updateData.fullName = req.body.fullName.trim();
        if (typeof req.body?.phoneNumber === 'string') updateData.phoneNumber = req.body.phoneNumber.trim();
        if (typeof req.body?.address === 'string') updateData.address = req.body.address.trim();

        const user = await User.findByIdAndUpdate(
            userId,
            { $set: updateData },
            { new: true }
        ).select('-password -resetCode -resetCodeExpiry');

        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        res.json(user);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Change password while signed in
// @route   POST /api/users/change-password
exports.changePassword = async (req, res) => {
    try {
        const currentPassword = typeof req.body?.currentPassword === 'string' ? req.body.currentPassword : '';
        const newPassword = typeof req.body?.newPassword === 'string' ? req.body.newPassword : '';

        if (!currentPassword || newPassword.length < 6) {
            return res.status(400).json({ message: 'Provide current password and a new password (min 6 characters)' });
        }

        const user = await User.findById(req.userId);
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        const matches = await bcrypt.compare(currentPassword, user.password);
        if (!matches) {
            return res.status(400).json({ message: 'Current password is incorrect' });
        }

        user.password = await bcrypt.hash(newPassword, 10);
        await user.save();

        res.json({ message: 'Password updated successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Delete own account and clean up device/parcel bindings
// @route   DELETE /api/users/:id
exports.deleteUser = async (req, res) => {
    try {
        const userId = req.params.id;

        if (userId !== req.userId) {
            return res.status(403).json({ message: 'Access denied: cannot delete another user\'s account' });
        }

        const user = await User.findByIdAndDelete(userId);
        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        // Remove user's tracking entries & owned rider badges
        await Tracking.deleteMany({ userId });
        await Rider.deleteMany({ userId });

        // Clean up any dropbox memberships
        const boxes = await Dropbox.find({
            $or: [{ userIds: userId }, { primaryUserId: userId }, { userId }]
        });
        const io = req.app.get('io');

        for (const box of boxes) {
            const remaining = (box.userIds || []).filter((id) => id !== userId);
            if (remaining.length === 0) {
                await Dropbox.updateOne(
                    { _id: box._id },
                    {
                        $set: {
                            userIds: [],
                            primaryUserId: null,
                            userId: null,
                            isRegistered: false,
                            name: 'Unregistered Device',
                            status: 'unregistered',
                            wifiSSID: null,
                        }
                    }
                );
                if (io) {
                    io.to(deviceRoom(box.deviceId)).emit('deviceUnregistered', { deviceId: box.deviceId });
                }
            } else {
                const nextPrimary = box.primaryUserId === userId ? remaining[0] : box.primaryUserId;
                await Dropbox.updateOne(
                    { _id: box._id },
                    {
                        $set: {
                            userIds: remaining,
                            primaryUserId: nextPrimary,
                            ...(box.userId === userId ? { userId: nextPrimary } : {})
                        }
                    }
                );
            }
        }

        res.json({ message: 'Account deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Request password reset - generates and sends reset code without user enumeration
// @route   POST /api/users/request-reset
exports.requestPasswordReset = async (req, res) => {
    try {
        const email = normalizeEmail(req.body?.email);
        if (!email) {
            return res.status(400).json({ message: 'Please provide a valid email address' });
        }

        const genericResponse = {
            message: 'If an account exists for that email, a reset code has been sent.'
        };

        const user = await User.findOne({ email });
        if (!user) {
            return res.json(genericResponse);
        }

        if (user.resetCodeLastSentAt && (Date.now() - user.resetCodeLastSentAt.getTime()) < RESET_COOLDOWN_MS) {
            return res.status(429).json({ message: 'Please wait a minute before requesting another code' });
        }

        const resetCode = crypto.randomInt(100000, 1000000).toString();
        const resetCodeExpiry = new Date(Date.now() + 15 * 60 * 1000);

        user.resetCode = resetCode;
        user.resetCodeExpiry = resetCodeExpiry;
        user.resetCodeAttempts = 0;
        user.resetCodeLastSentAt = new Date();
        await user.save();

        const emailSent = await sendResetCode(user.email, user.fullName, resetCode);
        if (!emailSent) {
            return res.status(500).json({ message: 'Failed to send reset email' });
        }

        res.json(genericResponse);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Verify reset code
// @route   POST /api/users/verify-reset-code
exports.verifyResetCode = async (req, res) => {
    try {
        const email = normalizeEmail(req.body?.email);
        const code = typeof req.body?.code === 'string' ? req.body.code.trim() : '';

        if (!email || !code) {
            return res.status(400).json({ message: 'Email and reset code are required' });
        }

        const user = await User.findOne({ email });
        if (!user) {
            return res.status(400).json({ message: 'Invalid or expired reset code' });
        }

        if (user.resetCodeAttempts >= RESET_MAX_ATTEMPTS) {
            return res.status(429).json({ message: 'Too many invalid attempts. Request a new reset code.' });
        }

        if (!user.resetCode || !user.resetCodeExpiry) {
            return res.status(400).json({ message: 'Invalid or expired reset code' });
        }

        if (new Date() > user.resetCodeExpiry) {
            return res.status(400).json({ message: 'Reset code has expired' });
        }

        if (user.resetCode !== code) {
            user.resetCodeAttempts = (user.resetCodeAttempts || 0) + 1;
            if (user.resetCodeAttempts >= RESET_MAX_ATTEMPTS) {
                user.resetCode = null;
                user.resetCodeExpiry = null;
            }
            await user.save();
            return res.status(400).json({ message: 'Invalid reset code' });
        }

        res.json({ message: 'Code verified successfully', valid: true });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Reset password with verified code
// @route   POST /api/users/reset-password
exports.resetPassword = async (req, res) => {
    try {
        const email = normalizeEmail(req.body?.email);
        const code = typeof req.body?.code === 'string' ? req.body.code.trim() : '';
        const newPassword = typeof req.body?.newPassword === 'string' ? req.body.newPassword : '';

        if (!email || !code || newPassword.length < 6) {
            return res.status(400).json({ message: 'Valid email, 6-digit code, and password (min 6 chars) are required' });
        }

        const user = await User.findOne({ email });
        if (!user) {
            return res.status(400).json({ message: 'Invalid or expired reset code' });
        }

        if (user.resetCodeAttempts >= RESET_MAX_ATTEMPTS) {
            return res.status(429).json({ message: 'Too many invalid attempts. Request a new reset code.' });
        }

        if (!user.resetCode || !user.resetCodeExpiry) {
            return res.status(400).json({ message: 'Invalid or expired reset code' });
        }

        if (new Date() > user.resetCodeExpiry) {
            return res.status(400).json({ message: 'Reset code has expired' });
        }

        if (user.resetCode !== code) {
            user.resetCodeAttempts = (user.resetCodeAttempts || 0) + 1;
            if (user.resetCodeAttempts >= RESET_MAX_ATTEMPTS) {
                user.resetCode = null;
                user.resetCodeExpiry = null;
            }
            await user.save();
            return res.status(400).json({ message: 'Invalid reset code' });
        }

        user.password = await bcrypt.hash(newPassword, 10);
        user.resetCode = null;
        user.resetCodeExpiry = null;
        user.resetCodeAttempts = 0;
        await user.save();

        res.json({ message: 'Password reset successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
