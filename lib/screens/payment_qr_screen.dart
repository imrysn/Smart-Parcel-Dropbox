import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/payment_service.dart';

/// GCash, Maya & Bank Payment QR & Invoice Generator Screen
class PaymentQrScreen extends StatefulWidget {
  const PaymentQrScreen({super.key});

  @override
  State<PaymentQrScreen> createState() => _PaymentQrScreenState();
}

class _PaymentQrScreenState extends State<PaymentQrScreen> {
  final PaymentService _paymentService = PaymentService();
  bool _isLoading = false;

  final _gcashNameController = TextEditingController();
  final _gcashNumberController = TextEditingController();
  final _mayaNameController = TextEditingController();
  final _mayaNumberController = TextEditingController();
  final _bankNameController = TextEditingController(text: 'BDO / BPI / UnionBank');
  final _bankAccountNameController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPaymentConfig();
  }

  @override
  void dispose() {
    _gcashNameController.dispose();
    _gcashNumberController.dispose();
    _mayaNameController.dispose();
    _mayaNumberController.dispose();
    _bankNameController.dispose();
    _bankAccountNameController.dispose();
    _bankAccountNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentConfig() async {
    setState(() => _isLoading = true);
    try {
      final config = await _paymentService.fetchPaymentConfig();
      if (mounted && config != null) {
        setState(() {
          _gcashNameController.text = config.gcashName ?? '';
          _gcashNumberController.text = config.gcashNumber ?? '';
          _mayaNameController.text = config.mayaName ?? '';
          _mayaNumberController.text = config.mayaNumber ?? '';
          _bankNameController.text = config.bankName ?? 'BDO / BPI / UnionBank';
          _bankAccountNameController.text = config.bankAccountName ?? '';
          _bankAccountNumberController.text = config.bankAccountNumber ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading payment config: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    // 1. OPTIMISTIC UI FEEDBACK
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment settings saved successfully!'), backgroundColor: UserTheme.statusSuccess),
      );
    }

    // 2. ASYNC BACKGROUND SYNC
    try {
      await _paymentService.savePaymentConfig(
        gcashName: _gcashNameController.text.trim(),
        gcashNumber: _gcashNumberController.text.trim(),
        mayaName: _mayaNameController.text.trim(),
        mayaNumber: _mayaNumberController.text.trim(),
        bankName: _bankNameController.text.trim(),
        bankAccountName: _bankAccountNameController.text.trim(),
        bankAccountNumber: _bankAccountNumberController.text.trim(),
      );
    } catch (e) {
      // 3. ROLLBACK / ERROR ALERT
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error. Settings failed to sync: $e'), backgroundColor: UserTheme.statusError),
        );
      }
    }
  }

  void _showGenerateInvoiceDialog() {
    final customerController = TextEditingController();
    final itemController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Payment Request'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: customerController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'e.g. Sarah Smith',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: itemController,
                decoration: const InputDecoration(
                  labelText: 'Order Item / Description',
                  hintText: 'e.g. Custom Resin Coaster Set',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Total Amount (₱)',
                  hintText: 'e.g. 450.00',
                  prefixText: '₱ ',
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
              Navigator.of(context).pop();

              try {
                final res = await _paymentService.generateInvoice(
                  customerName: customerController.text.trim(),
                  orderItem: itemController.text.trim(),
                  amount: amount,
                );

                final text = res['text'] ?? '';
                await Clipboard.setData(ClipboardData(text: text));

                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Payment Request Generated!'),
                      content: SingleChildScrollView(
                        child: Text(text),
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('DONE (COPIED TO CLIPBOARD)'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error generating invoice: $e');
              }
            },
            child: const Text('GENERATE & COPY'),
          ),
        ],
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
            'Payment Settings (GCash/Maya/Bank)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Action Card
                    UserUi.surfaceCard(
                      context,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Generate Payment Requests for IG/TikTok Buyers',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Save your GCash, Maya, and Bank transfer details below. Generate formatted payment request cards with 1 tap.',
                            style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          UserUi.premiumButton(
                            label: 'GENERATE CUSTOMER PAYMENT REQUEST',
                            onTap: _showGenerateInvoiceDialog,
                            icon: Icons.qr_code_2_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 1: GCash Details
                    _buildSectionHeader('🟦 GCash Merchant Details'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _gcashNameController,
                      decoration: const InputDecoration(
                        labelText: 'GCash Account Name',
                        hintText: 'e.g. Sarah S.',
                        prefixIcon: Icon(Icons.account_box_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _gcashNumberController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'GCash Mobile Number',
                        hintText: 'e.g. 09171234567',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 2: Maya Details
                    _buildSectionHeader('🟩 Maya Merchant Details'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _mayaNameController,
                      decoration: const InputDecoration(
                        labelText: 'Maya Account Name',
                        hintText: 'e.g. Sarah S.',
                        prefixIcon: Icon(Icons.account_box_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _mayaNumberController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Maya Mobile Number',
                        hintText: 'e.g. 09189876543',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section 3: Bank Transfer Details (BDO / BPI / UnionBank)
                    _buildSectionHeader('🏦 Bank Transfer Details (BDO / BPI / UnionBank)'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bankNameController,
                      decoration: const InputDecoration(
                        labelText: 'Bank Name',
                        hintText: 'e.g. BDO / BPI / UnionBank',
                        prefixIcon: Icon(Icons.account_balance_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bankAccountNameController,
                      decoration: const InputDecoration(
                        labelText: 'Bank Account Name',
                        hintText: 'e.g. Sarah Smith',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bankAccountNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bank Account Number',
                        hintText: 'e.g. 001234567890',
                        prefixIcon: Icon(Icons.credit_card_rounded),
                      ),
                    ),
                    const SizedBox(height: 28),

                    ElevatedButton.icon(
                      onPressed: _saveConfig,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('SAVE PAYMENT SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UserTheme.primaryOrange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        final gcash = _gcashNumberController.text.isNotEmpty ? "🔹 GCash: ${_gcashNumberController.text.trim()} (${_gcashNameController.text.trim()})" : "";
                        final maya = _mayaNumberController.text.isNotEmpty ? "🔹 Maya: ${_mayaNumberController.text.trim()} (${_mayaNameController.text.trim()})" : "";
                        final bank = _bankAccountNumberController.text.isNotEmpty ? "🔹 ${_bankNameController.text.trim()}: ${_bankAccountNumberController.text.trim()} (${_bankAccountNameController.text.trim()})" : "";

                        final formatted = "💳 PAYMENT DETAILS:\n$gcash\n$maya\n$bank\n\nPlease send proof of payment once completed. Thank you!";
                        Clipboard.setData(ClipboardData(text: formatted));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Payment details copied for customer DMs!'), backgroundColor: UserTheme.statusSuccess),
                        );
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: const Text('COPY FORMATTED PAYMENT INFO FOR DMs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: UserTheme.primaryOrange,
                        side: const BorderSide(color: UserTheme.primaryOrange, width: 1.5),
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
      ),
    );
  }
}
