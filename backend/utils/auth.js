const jwt = require('jsonwebtoken');

const JWT_EXPIRES_IN = '7d'; // Token expires in 7 days

function signingKey() {
    const key = process.env.JWT_SECRET;
    if (!key || key.length < 32) throw new Error('JWT_SECRET must contain at least 32 characters');
    return key;
}

exports.checkSigningKey = signingKey;

// Generate JWT token
exports.generateToken = (userId) => {
    return jwt.sign({ userId }, signingKey(), { expiresIn: JWT_EXPIRES_IN });
};

// Verify JWT token
exports.verifyToken = (token) => {
    try {
        return jwt.verify(token, signingKey(), { algorithms: ['HS256'] });
    } catch (error) {
        return null;
    }
};

// Middleware to protect routes
exports.authMiddleware = (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1]; // Bearer TOKEN

        if (!token) {
            return res.status(401).json({ message: 'No token provided' });
        }

        const decoded = exports.verifyToken(token);

        if (!decoded) {
            return res.status(401).json({ message: 'Invalid or expired token' });
        }

        req.userId = decoded.userId;
        req.sessionExpiresAt = decoded.exp * 1000;
        next();
    } catch (error) {
        res.status(401).json({ message: 'Authentication failed' });
    }
};
