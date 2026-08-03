const PaymentQr = require('../models/PaymentQr');

/**
 * GET /api/payments/config
 * Fetch payment settings for logged-in user
 */
exports.getPaymentConfig = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    let config = await PaymentQr.findOne({ userId });

    if (!config) {
      config = {
        userId,
        gcashName: '',
        gcashNumber: '',
        mayaName: '',
        mayaNumber: '',
        bankName: 'BDO / BPI / UnionBank',
        bankAccountName: '',
        bankAccountNumber: '',
        qrPhImageUrl: ''
      };
    }

    res.json({
      success: true,
      data: config
    });
  } catch (err) {
    console.error('❌ getPaymentConfig error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/payments/config
 * Save / Update merchant payment settings (GCash, Maya, Bank)
 */
exports.savePaymentConfig = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { gcashName, gcashNumber, mayaName, mayaNumber, bankName, bankAccountName, bankAccountNumber, qrPhImageUrl } = req.body;

    const updated = await PaymentQr.findOneAndUpdate(
      { userId },
      {
        userId,
        gcashName: gcashName || '',
        gcashNumber: gcashNumber || '',
        mayaName: mayaName || '',
        mayaNumber: mayaNumber || '',
        bankName: bankName || 'BDO / BPI / UnionBank',
        bankAccountName: bankAccountName || '',
        bankAccountNumber: bankAccountNumber || '',
        qrPhImageUrl: qrPhImageUrl || ''
      },
      { upsert: true, new: true }
    );

    res.json({
      success: true,
      message: 'Payment configuration saved',
      data: updated
    });
  } catch (err) {
    console.error('❌ savePaymentConfig error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/payments/generate-invoice
 * Generates customer payment receipt text with GCash, Maya & Bank details
 */
exports.generateInvoice = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { customerName, orderItem, amount } = req.body;

    const config = await PaymentQr.findOne({ userId });

    const numAmount = parseFloat(amount || 0).toFixed(2);
    const customer = customerName || 'Valued Customer';
    const item = orderItem || 'Custom Craft Order';

    let paymentOptionsText = '';
    if (config) {
      if (config.gcashNumber) {
        paymentOptionsText += `• GCash: ${config.gcashNumber} (${config.gcashName || 'Merchant'})\n`;
      }
      if (config.mayaNumber) {
        paymentOptionsText += `• Maya: ${config.mayaNumber} (${config.mayaName || 'Merchant'})\n`;
      }
      if (config.bankAccountNumber) {
        paymentOptionsText += `• Bank (${config.bankName || 'Bank'}): ${config.bankAccountNumber} (${config.bankAccountName || 'Merchant'})\n`;
      }
    }

    if (!paymentOptionsText) {
      paymentOptionsText = `• GCash / Maya / Bank Transfer available upon request.\n`;
    }

    const invoiceText = `Hi ${customer}! Thank you for your order for "${item}".\n\n💰 Total Amount Due: ₱${numAmount}\n\n💳 Payment Options:\n${paymentOptionsText}\nPlease send a screenshot of your payment receipt once completed. Thank you! 🎨✨`;

    res.json({
      success: true,
      data: {
        text: invoiceText,
        shareText: invoiceText
      }
    });
  } catch (err) {
    console.error('❌ generateInvoice error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};
