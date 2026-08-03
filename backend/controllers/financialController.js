const Transaction = require('../models/Transaction');

/**
 * GET /api/financial/summary
 * Returns Gross Revenue, Total Expenses, Net Profit, Net Margin %, and recent transactions.
 */
exports.getFinancialSummary = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const transactions = await Transaction.find({ userId }).sort({ date: -1 });

    let grossRevenue = 0;
    let totalExpenses = 0;
    let shippingExpenses = 0;
    let materialExpenses = 0;

    transactions.forEach(t => {
      if (t.type === 'REVENUE') {
        grossRevenue += t.amount;
      } else {
        totalExpenses += t.amount;
        if (t.type === 'EXPENSE_SHIPPING') shippingExpenses += t.amount;
        if (t.type === 'EXPENSE_MATERIAL') materialExpenses += t.amount;
      }
    });

    const netProfit = grossRevenue - totalExpenses;
    const marginPercent = grossRevenue > 0 ? ((netProfit / grossRevenue) * 100).toFixed(1) : '0.0';

    res.json({
      success: true,
      data: {
        summary: {
          grossRevenue,
          totalExpenses,
          shippingExpenses,
          materialExpenses,
          netProfit,
          marginPercent: parseFloat(marginPercent)
        },
        recentTransactions: transactions.slice(0, 15),
        allTransactions: transactions
      }
    });
  } catch (err) {
    console.error('❌ getFinancialSummary error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/financial/transactions
 * Create a new revenue or expense transaction
 */
exports.createTransaction = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { type, amount, category, description, referenceId, date } = req.body;

    if (!type || amount === undefined) {
      return res.status(400).json({ success: false, message: 'Type and amount are required' });
    }

    const numAmount = parseFloat(amount);
    if (isNaN(numAmount) || numAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Amount must be a positive number' });
    }

    const newTx = await Transaction.create({
      userId,
      type,
      amount: numAmount,
      category: category || 'General',
      description: description || '',
      referenceId: referenceId || '',
      date: date ? new Date(date) : new Date()
    });

    res.status(201).json({
      success: true,
      message: 'Transaction recorded successfully',
      data: newTx
    });
  } catch (err) {
    console.error('❌ createTransaction error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * DELETE /api/financial/transactions/:id
 * Delete a transaction
 */
exports.deleteTransaction = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { id } = req.params;

    const tx = await Transaction.findOneAndDelete({ _id: id, userId });
    if (!tx) {
      return res.status(404).json({ success: false, message: 'Transaction not found' });
    }

    res.json({ success: true, message: 'Transaction deleted' });
  } catch (err) {
    console.error('❌ deleteTransaction error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * GET /api/financial/export
 * Download CSV ledger
 */
exports.exportCsv = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const transactions = await Transaction.find({ userId }).sort({ date: -1 });

    let csv = 'ID,Date,Type,Category,Description,Amount (₱)\n';
    transactions.forEach(t => {
      const dateStr = new Date(t.date).toISOString().split('T')[0];
      csv += `"${t._id}","${dateStr}","${t.type}","${t.category}","${t.description || ''}",${t.amount.toFixed(2)}\n`;
    });

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="financial_ledger.csv"');
    res.send(csv);
  } catch (err) {
    console.error('❌ exportCsv error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * POST /api/financial/sync-inbound-supply
 * Auto-links an inbound Shopee/TikTok supply parcel to a Craft Supply Expense in the Financial Ledger
 */
exports.syncInboundSupplyExpense = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const { trackingId, amount, supplyName } = req.body;

    if (!trackingId || amount === undefined) {
      return res.status(400).json({ success: false, message: 'trackingId and amount are required' });
    }

    const numAmount = parseFloat(amount);
    if (isNaN(numAmount) || numAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Amount must be a positive number' });
    }

    const tx = await Transaction.create({
      userId,
      type: 'EXPENSE_MATERIAL',
      amount: numAmount,
      category: 'Inbound Craft Supply',
      description: `${supplyName || 'Shopee/TikTok Craft Supply'} (Waybill #${trackingId})`,
      referenceId: trackingId,
      date: new Date()
    });

    res.status(201).json({
      success: true,
      message: 'Inbound supply expense synced to Financial Ledger',
      data: tx
    });
  } catch (err) {
    console.error('❌ syncInboundSupplyExpense error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};

/**
 * GET /api/financial/analytics
 * Returns 30-day daily cash flow breakdown & 30-day projection velocity
 */
exports.getFinancialAnalytics = async (req, res) => {
  try {
    const userId = req.userId || req.user?.userId;
    const Task = require('../models/Task');

    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const transactions = await Transaction.find({
      userId,
      date: { $gte: thirtyDaysAgo }
    }).sort({ date: 1 });

    const dailyMap = {};
    for (let i = 0; i < 30; i++) {
      const d = new Date();
      d.setDate(d.getDate() - (29 - i));
      const key = d.toISOString().split('T')[0];
      dailyMap[key] = { date: key, revenue: 0, expense: 0, net: 0 };
    }

    transactions.forEach(t => {
      const key = new Date(t.date).toISOString().split('T')[0];
      if (dailyMap[key]) {
        if (t.type === 'REVENUE') {
          dailyMap[key].revenue += t.amount;
        } else {
          dailyMap[key].expense += t.amount;
        }
        dailyMap[key].net = dailyMap[key].revenue - dailyMap[key].expense;
      }
    });

    const dailyTrends = Object.values(dailyMap);

    const total30Rev = dailyTrends.reduce((sum, d) => sum + d.revenue, 0);
    const total30Exp = dailyTrends.reduce((sum, d) => sum + d.expense, 0);
    const dailyVelocity = parseFloat((total30Rev / 30).toFixed(2));

    const pendingTasks = await Task.find({
      userId,
      stage: { $in: ['INQUIRY', 'CRAFTING', 'READY_FOR_BOX'] }
    });

    const pipelineProjectedRevenue = pendingTasks.length * 850;
    const forecast30DaysNet = parseFloat((total30Rev + pipelineProjectedRevenue - total30Exp).toFixed(2));

    res.json({
      success: true,
      data: {
        dailyTrends,
        metrics: {
          total30DayRevenue: total30Rev,
          total30DayExpense: total30Exp,
          dailyVelocity,
          pipelineCount: pendingTasks.length,
          pipelineProjectedRevenue,
          forecast30DaysNet
        }
      }
    });
  } catch (err) {
    console.error('❌ getFinancialAnalytics error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
};
