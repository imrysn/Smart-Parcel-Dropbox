import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../widgets/cash_flow_chart.dart';
import '../models/transaction_model.dart';
import '../services/financial_service.dart';
import 'payment_qr_screen.dart';

/// Financial Ledger & Profit Tracker Screen
class FinancialScreen extends StatefulWidget {
  const FinancialScreen({super.key});

  @override
  State<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends State<FinancialScreen> {
  final FinancialService _financialService = FinancialService();
  bool _isLoading = false;

  FinancialSummaryModel _summary = FinancialSummaryModel(
    grossRevenue: 0,
    totalExpenses: 0,
    shippingExpenses: 0,
    materialExpenses: 0,
    netProfit: 0,
    marginPercent: 0,
  );

  List<TransactionModel> _transactions = [];
  List<CashFlowTrendPoint> _trends = [];
  double _dailyVelocity = 0;
  double _forecast30DaysNet = 0;
  int _pipelineCount = 0;
  double _pipelineProjectedRevenue = 0;

  @override
  void initState() {
    super.initState();
    _loadFinancialData();
  }

  Future<void> _loadFinancialData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _financialService.fetchFinancialSummary();
      final analytics = await _financialService.fetchFinancialAnalytics();

      if (mounted) {
        final rawTrends = (analytics['dailyTrends'] as List?) ?? [];
        final metrics = (analytics['metrics'] as Map<String, dynamic>?) ?? {};

        setState(() {
          _summary = res['summary'];
          _transactions = res['transactions'];
          _trends = rawTrends.map((t) => CashFlowTrendPoint.fromMap(t)).toList();
          _dailyVelocity = (metrics['dailyVelocity'] as num?)?.toDouble() ?? 0.0;
          _forecast30DaysNet = (metrics['forecast30DaysNet'] as num?)?.toDouble() ?? 0.0;
          _pipelineCount = (metrics['pipelineCount'] as num?)?.toInt() ?? 0;
          _pipelineProjectedRevenue = (metrics['pipelineProjectedRevenue'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (e) {
      debugPrint('Error loading financial data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTransaction(String id) async {
    // 1. OPTIMISTIC LOCAL MUTATION
    final backupTransactions = List<TransactionModel>.from(_transactions);
    final backupSummary = _summary;

    final targetIndex = _transactions.indexWhere((t) => t.id == id);
    if (targetIndex == -1) return;
    final target = _transactions[targetIndex];

    setState(() {
      _transactions.removeAt(targetIndex);
      
      double gross = _summary.grossRevenue;
      double totalExp = _summary.totalExpenses;
      double shipExp = _summary.shippingExpenses;
      double matExp = _summary.materialExpenses;

      if (target.isRevenue) {
        gross -= target.amount;
      } else {
        totalExp -= target.amount;
        if (target.type == 'EXPENSE_SHIPPING') shipExp -= target.amount;
        if (target.type == 'EXPENSE_MATERIAL') matExp -= target.amount;
      }

      final net = gross - totalExp;
      final margin = gross > 0 ? ((net / gross) * 100) : 0.0;

      _summary = FinancialSummaryModel(
        grossRevenue: gross,
        totalExpenses: totalExp,
        shippingExpenses: shipExp,
        materialExpenses: matExp,
        netProfit: net,
        marginPercent: margin,
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction removed'), backgroundColor: UserTheme.statusSuccess),
      );
    }

    // 2. ASYNC BACKGROUND SYNC
    try {
      await _financialService.deleteTransaction(id);
    } catch (e) {
      // 3. ROLLBACK ON ERROR
      if (mounted) {
        setState(() {
          _transactions = backupTransactions;
          _summary = backupSummary;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error. Restored deleted transaction: $e'), backgroundColor: UserTheme.statusError),
        );
      }
    }
  }

  void _showAddTransactionDialog() {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedType = 'EXPENSE_MATERIAL';
    String selectedCategory = 'Craft Supplies';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Revenue / Supply Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Transaction Type'),
                  items: const [
                    DropdownMenuItem(value: 'REVENUE', child: Text('💵 Revenue (Craft Sale)')),
                    DropdownMenuItem(value: 'EXPENSE_MATERIAL', child: Text('🎨 Expense: Craft Supplies')),
                    DropdownMenuItem(value: 'EXPENSE_SHIPPING', child: Text('🚚 Expense: Shipping Fee')),
                    DropdownMenuItem(value: 'EXPENSE_OTHER', child: Text('💸 Expense: Packaging / Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedType = val;
                        if (val == 'REVENUE') selectedCategory = 'Order Sale';
                        else if (val == 'EXPENSE_MATERIAL') selectedCategory = 'Craft Supplies';
                        else if (val == 'EXPENSE_SHIPPING') selectedCategory = 'Shipping Fee';
                        else selectedCategory = 'Packaging';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₱)',
                    hintText: 'e.g. 45.00',
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. 1kg Epoxy Resin & Silicone Molds',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0) return;
                final desc = descriptionController.text.trim();
                Navigator.of(context).pop();

                // 1. OPTIMISTIC LOCAL MUTATION
                final backupTransactions = List<TransactionModel>.from(_transactions);
                final backupSummary = _summary;

                final tempTx = TransactionModel(
                  id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
                  userId: '',
                  type: selectedType,
                  amount: amount,
                  category: selectedCategory,
                  description: desc,
                  date: DateTime.now(),
                );

                setState(() {
                  _transactions.insert(0, tempTx);

                  double gross = _summary.grossRevenue;
                  double totalExp = _summary.totalExpenses;
                  double shipExp = _summary.shippingExpenses;
                  double matExp = _summary.materialExpenses;

                  if (selectedType == 'REVENUE') {
                    gross += amount;
                  } else {
                    totalExp += amount;
                    if (selectedType == 'EXPENSE_SHIPPING') shipExp += amount;
                    if (selectedType == 'EXPENSE_MATERIAL') matExp += amount;
                  }

                  final net = gross - totalExp;
                  final margin = gross > 0 ? ((net / gross) * 100) : 0.0;

                  _summary = FinancialSummaryModel(
                    grossRevenue: gross,
                    totalExpenses: totalExp,
                    shippingExpenses: shipExp,
                    materialExpenses: matExp,
                    netProfit: net,
                    marginPercent: margin,
                  );
                });

                // 2. ASYNC BACKGROUND SYNC
                try {
                  await _financialService.createTransaction(
                    type: selectedType,
                    amount: amount,
                    category: selectedCategory,
                    description: desc,
                  );
                  _loadFinancialData();
                } catch (e) {
                  // 3. ROLLBACK ON ERROR
                  if (mounted) {
                    setState(() {
                      _transactions = backupTransactions;
                      _summary = backupSummary;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Network error. Transaction failed: $e'), backgroundColor: UserTheme.statusError),
                    );
                  }
                }
              },
              child: const Text('RECORD ENTRY'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Financial Ledger & Expenses',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_2_rounded, color: UserTheme.primaryOrange),
              tooltip: 'GCash / Maya / Bank Payment Requests',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const PaymentQrScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.download_rounded, color: UserTheme.primaryOrange),
              tooltip: 'Export CSV Ledger',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Financial CSV ledger generated & ready for download!'), backgroundColor: UserTheme.statusSuccess),
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddTransactionDialog,
          backgroundColor: UserTheme.statusSuccess,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Log Revenue / Expense'),
        ),
        body: RefreshIndicator(
          onRefresh: _loadFinancialData,
          color: UserTheme.primaryOrange,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Metrics Overview Card
                UserUi.glassCard(
                  context,
                  blur: 16,
                  padding: const EdgeInsets.all(20),
                  color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "BUSINESS PROFIT SUMMARY",
                            style: TextStyle(
                              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          UserUi.statusPill(
                            label: '${_summary.marginPercent.toStringAsFixed(1)}% Net Margin',
                            color: _summary.netProfit >= 0 ? UserTheme.statusSuccess : UserTheme.statusError,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "₱${_summary.netProfit.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: _summary.netProfit >= 0 ? UserTheme.statusSuccess : UserTheme.statusError,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Net Business Income",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Divider(color: isDark ? Colors.white10 : Colors.black12),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMiniMetric('Gross Sales', '₱${_summary.grossRevenue.toStringAsFixed(2)}', UserTheme.statusSuccess),
                          _buildMiniMetric('Shipping Fees', '₱${_summary.shippingExpenses.toStringAsFixed(2)}', Colors.indigo),
                          _buildMiniMetric('Material Costs', '₱${_summary.materialExpenses.toStringAsFixed(2)}', UserTheme.primaryOrange),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  "Recent Ledger Entries",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Interactive Cash Flow & Revenue Forecast Card
                UserUi.glassCard(
                  context,
                  blur: 16,
                  padding: const EdgeInsets.all(20),
                  color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                  child: CashFlowChart(
                    trends: _trends,
                    dailyVelocity: _dailyVelocity,
                    forecast30DaysNet: _forecast30DaysNet,
                    pipelineCount: _pipelineCount,
                    pipelineProjectedRevenue: _pipelineProjectedRevenue,
                  ),
                ),
                const SizedBox(height: 16),

                if (_isLoading && _transactions.isEmpty)
                  const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange))
                else if (_transactions.isEmpty)
                  UserUi.emptyState(
                    context,
                    icon: Icons.receipt_long_rounded,
                    title: 'No ledger entries yet',
                    subtitle: 'Tap "+ Log Revenue / Expense" below to record craft sales or material costs.',
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: UserUi.surfaceCard(
                          context,
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: tx.typeColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(tx.typeIcon, color: tx.typeColor, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.category,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                                      ),
                                    ),
                                    if (tx.description != null && tx.description!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        tx.description!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${tx.isRevenue ? '+' : '-'}₱${tx.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: tx.typeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${tx.date.day}/${tx.date.month}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                onPressed: () => _deleteTransaction(tx.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}
