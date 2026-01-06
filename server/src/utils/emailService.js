const nodemailer = require('nodemailer');
require('dotenv').config();

const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: process.env.EMAIL_USER, // Your Gmail address
        pass: process.env.EMAIL_PASS  // Your Gmail App Password
    }
});

// Verify connection configuration
transporter.verify(function (error, success) {
    if (error) {
        console.log('[EMAIL_SERVICE] Server is NOT ready to send emails:', error);
    } else {
        console.log('[EMAIL_SERVICE] Server is ready to take our messages');
    }
});

exports.sendResetCode = async (email, fullName, resetCode) => {
    console.log(`[EMAIL_SERVICE] Attempting to send reset code to: ${email}`);
    try {
        const mailOptions = {
            from: `"Smart Parcel System" <${process.env.EMAIL_USER}>`,
            to: email,
            subject: 'Password Reset Code - Smart Parcel System',
            html: `
                <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px;">
                    <h2 style="color: #FFB300; text-align: center;">Smart Parcel Drop Box</h2>
                    <p>Hello <strong>${fullName || 'User'}</strong>,</p>
                    <p>We received a request to reset the password for your account associated with <strong>${email}</strong>.</p>
                    
                    <div style="background-color: #f5f5f5; padding: 20px; border-radius: 5px; margin: 20px 0; text-align: center;">
                        <p style="margin: 0; font-size: 14px; color: #666;">Your password reset code is:</p>
                        <h1 style="color: #FFB300; font-size: 36px; letter-spacing: 8px; margin: 10px 0;">${resetCode}</h1>
                        <p style="margin: 0; font-size: 12px; color: #999;">This code will expire in 15 minutes</p>
                    </div>
                    
                    <p>Enter this code in the app to reset your password.</p>
                    
                    <div style="background-color: #fff9c4; padding: 15px; border-radius: 5px; margin: 20px 0;">
                        <p style="margin: 0; color: #5d4037; font-size: 14px;">
                            <strong>Security Note:</strong> If you did <strong>not</strong> request a password reset, please ignore this email or contact support immediately.
                        </p>
                    </div>
                    
                    <p>Best regards,<br>The Smart Parcel Team</p>
                    <hr style="border: none; border-top: 1px solid #eee; margin-top: 30px;">
                    <p style="font-size: 12px; color: #9e9e9e; text-align: center;">
                        This is an automated message. Please do not reply to this email.
                    </p>
                </div>
            `
        };

        const info = await transporter.sendMail(mailOptions);
        console.log('[EMAIL_SERVICE] Reset code email sent: ' + info.response);
        return true;
    } catch (error) {
        console.error('[EMAIL_SERVICE] Error sending email:', error);
        return false;
    }
};
