const User = require('../models/User');
const { sendResetCode } = require('../utils/emailService');
const { generateToken } = require('../utils/auth');
const bcrypt = require('bcryptjs');

// @desc    Register a new user
// @route   POST /api/users/register
exports.registerUser = async (req, res) => {
    try {
        const { email, password, fullName, phoneNumber, address } = req.body;
        console.log(`[USER_CONTROLLER] Registering user: ${email}`);

        // Check if user already exists
        let user = await User.findOne({ email: email.toLowerCase() });

        if (user) {
            console.log(`[USER_CONTROLLER] User already exists: ${email}`);
            return res.status(400).json({ message: 'User already exists' });
        }

        // Hash password
        const hashedPassword = await bcrypt.hash(password, 10);

        // Create user
        user = await User.create({
            email: email.toLowerCase(),
            password: hashedPassword,
            fullName,
            phoneNumber,
            address,
            role: 'user'
        });

        // Generate JWT token
        const token = generateToken(user._id);

        res.status(201).json({
            message: 'User registered successfully',
            token,
            user: {
                id: user._id,
                email: user.email,
                fullName: user.fullName,
                role: user.role
            }
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
        const { email, password } = req.body;
        console.log(`[USER_CONTROLLER] Login attempt: ${email}`);

        // Find user
        const user = await User.findOne({ email: email.toLowerCase() });

        if (!user) {
            return res.status(401).json({ message: 'Invalid email or password' });
        }

        // Check password
        const isPasswordValid = await bcrypt.compare(password, user.password);

        if (!isPasswordValid) {
            return res.status(401).json({ message: 'Invalid email or password' });
        }

        // Generate JWT token
        const token = generateToken(user._id);

        console.log(`[USER_CONTROLLER] Login successful: ${user.email}`);
        res.json({
            message: 'Login successful',
            token,
            user: {
                id: user._id,
                email: user.email,
                fullName: user.fullName,
                role: user.role,
                phoneNumber: user.phoneNumber,
                address: user.address
            }
        });
    } catch (error) {
        console.error('[USER_CONTROLLER] Login error:', error);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get user profile
// @route   GET /api/users/:id
exports.getUserProfile = async (req, res) => {
    try {
        const userId = req.params.id;
        console.log(`[USER_CONTROLLER] Fetching profile for ID: ${userId}`);

        const user = await User.findById(userId).select('-password');

        if (!user) {
            console.log(`[USER_CONTROLLER] Profile NOT FOUND for ID: ${userId}`);
            return res.status(404).json({ message: 'User not found' });
        }

        console.log(`[USER_CONTROLLER] Profile found: ${user.email} (Role: ${user.role})`);
        res.json(user);
    } catch (error) {
        console.error(`[USER_CONTROLLER] Error fetching profile: ${error.message}`);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get all users (Admin only)
// @route   GET /api/users
exports.getAllUsers = async (req, res) => {
    try {
        const users = await User.find().select('-password').sort({ createdAt: -1 });
        res.json(users);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Update user profile
// @route   PATCH /api/users/:id
exports.updateUser = async (req, res) => {
    try {
        const userId = req.params.id;
        console.log(`[USER_CONTROLLER] Updating user: ${userId}`);
        console.log(`[USER_CONTROLLER] Update body:`, req.body);

        // Don't allow password updates through this endpoint
        const { password, ...updateData } = req.body;

        const user = await User.findByIdAndUpdate(
            userId,
            { $set: updateData },
            { new: true }
        ).select('-password');

        if (!user) {
            console.log(`[USER_CONTROLLER] User not found for update: ${userId}`);
            return res.status(404).json({ message: 'User not found' });
        }

        console.log(`[USER_CONTROLLER] User updated successfully: ${user._id}`);
        res.json(user);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Delete user
// @route   DELETE /api/users/:id
exports.deleteUser = async (req, res) => {
    try {
        const userId = req.params.id;
        console.log(`[USER_CONTROLLER] Deleting user: ${userId}`);

        const user = await User.findByIdAndDelete(userId);

        if (!user) {
            console.log(`[USER_CONTROLLER] User not found for deletion: ${userId}`);
            return res.status(404).json({ message: 'User not found' });
        }

        console.log(`[USER_CONTROLLER] User deleted successfully: ${userId}`);
        res.json({ message: 'User deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Check if user exists by email
// @route   GET /api/users/check-email/:email
exports.checkUserByEmail = async (req, res) => {
    try {
        const { email } = req.params;
        console.log(`[USER_CONTROLLER] Checking existence for email: ${email}`);
        const user = await User.findOne({ email: email.toLowerCase() });

        if (!user) {
            return res.status(404).json({ exists: false, message: 'User not found' });
        }

        res.json({ exists: true, id: user._id });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Request password reset - generates and sends reset code
// @route   POST /api/users/request-reset
exports.requestPasswordReset = async (req, res) => {
    try {
        const { email } = req.body;
        const user = await User.findOne({ email: email.toLowerCase() });

        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        // Generate 6-digit reset code
        const resetCode = Math.floor(100000 + Math.random() * 900000).toString();

        // Set expiry to 15 minutes from now
        const resetCodeExpiry = new Date(Date.now() + 15 * 60 * 1000);

        // Save reset code to MongoDB
        user.resetCode = resetCode;
        user.resetCodeExpiry = resetCodeExpiry;
        await user.save();

        // Send email with reset code
        const emailSent = await sendResetCode(user.email, user.fullName, resetCode);

        if (emailSent) {
            res.json({ message: 'Reset code sent to your email' });
        } else {
            res.status(500).json({ message: 'Failed to send email' });
        }
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Verify reset code
// @route   POST /api/users/verify-reset-code
exports.verifyResetCode = async (req, res) => {
    try {
        const { email, code } = req.body;
        const user = await User.findOne({ email: email.toLowerCase() });

        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        if (!user.resetCode || !user.resetCodeExpiry) {
            return res.status(400).json({ message: 'No reset code requested' });
        }

        if (new Date() > user.resetCodeExpiry) {
            return res.status(400).json({ message: 'Reset code has expired' });
        }

        if (user.resetCode !== code) {
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
        const { email, code, newPassword } = req.body;
        const user = await User.findOne({ email: email.toLowerCase() });

        if (!user) {
            return res.status(404).json({ message: 'User not found' });
        }

        if (!user.resetCode || !user.resetCodeExpiry) {
            return res.status(400).json({ message: 'No reset code requested' });
        }

        if (new Date() > user.resetCodeExpiry) {
            return res.status(400).json({ message: 'Reset code has expired' });
        }

        if (user.resetCode !== code) {
            return res.status(400).json({ message: 'Invalid reset code' });
        }

        // Hash new password
        const hashedPassword = await bcrypt.hash(newPassword, 10);
        user.password = hashedPassword;

        // Clear reset code
        user.resetCode = null;
        user.resetCodeExpiry = null;
        await user.save();

        res.json({ message: 'Password reset successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
