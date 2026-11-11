const express = require('express');
const router = express.Router();
const { getFinancialSummary, createTransaction, deleteTransaction, exportCsv, syncInboundSupplyExpense, getFinancialAnalytics } = require('../controllers/financialController');
const { authMiddleware } = require('../utils/auth');

router.use(authMiddleware);

router.get('/summary', getFinancialSummary);
router.get('/analytics', getFinancialAnalytics);
router.post('/transactions', createTransaction);
router.delete('/transactions/:id', deleteTransaction);
router.get('/export', exportCsv);
router.post('/sync-inbound-supply', syncInboundSupplyExpense);

module.exports = router;
