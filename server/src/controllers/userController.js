const User = require('../models/User');

// @desc    Register a new user
// @route   POST /api/users
exports.registerUser = async (req, res) => {
    try {
        const { uid, email, fullName, phoneNumber, address, role } = req.body;
        console.log(`[USER_CONTROLLER] Registering user: ${uid} (${email})`);

        let user = await User.findOne({ uid });

        if (user) {
            console.log(`[USER_CONTROLLER] User already exists: ${uid}`);
            return res.status(400).json({ message: 'User already exists' });
        }

        user = await User.create({
            uid,
            email,
            fullName,
            phoneNumber,
            address,
            role
        });

        res.status(201).json(user);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get user profile
exports.getUserProfile = async (req, res) => {
    try {
        console.log(`[USER_CONTROLLER] Fetching profile for UID: ${req.params.uid}`);
        const user = await User.findOne({ uid: req.params.uid });

        if (!user) {
            console.log(`[USER_CONTROLLER] Profile NOT FOUND for UID: ${req.params.uid}`);
            return res.status(404).json({ message: 'User not found' });
        }

        console.log(`[USER_CONTROLLER] Profile found: ${user.email} (Role: ${user.role})`);
        res.json(user);
    } catch (error) {
        console.error(`[USER_CONTROLLER] Error fetching profile: ${error.message}`);
        res.status(500).json({ message: error.message });
    }
};

// @desc    Get all users
// @route   GET /api/users
exports.getAllUsers = async (req, res) => {
    try {
        const users = await User.find().sort({ createdAt: -1 });
        res.json(users);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Update user profile
// @route   PATCH /api/users/:uid
exports.updateUser = async (req, res) => {
    try {
        console.log(`[USER_CONTROLLER] Updating user: ${req.params.uid}`);
        console.log(`[USER_CONTROLLER] Update body:`, req.body);

        const user = await User.findOneAndUpdate(
            { uid: req.params.uid },
            { $set: req.body },
            { new: true }
        );

        if (!user) {
            console.log(`[USER_CONTROLLER] User not found for update: ${req.params.uid}`);
            return res.status(404).json({ message: 'User not found' });
        }

        console.log(`[USER_CONTROLLER] User updated successfully: ${user.uid}`);
        res.json(user);
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Delete user
// @route   DELETE /api/users/:uid
exports.deleteUser = async (req, res) => {
    try {
        console.log(`[USER_CONTROLLER] Deleting user: ${req.params.uid}`);
        const user = await User.findOneAndDelete({ uid: req.params.uid });

        if (!user) {
            console.log(`[USER_CONTROLLER] User not found for deletion: ${req.params.uid}`);
            return res.status(404).json({ message: 'User not found' });
        }

        console.log(`[USER_CONTROLLER] User deleted successfully: ${req.params.uid}`);
        res.json({ message: 'User deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};
