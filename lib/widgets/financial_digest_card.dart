import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../config/user_theme.dart';
import 'user_ui.dart';

class FinancialDigestCard extends StatelessWidget {
  final FinancialSummaryModel summary;
  final VoidCallback? onTapViewLedger;

  const FinancialDigestCard({
    super.key,
    required this.summary,
    this.onTapViewLedger,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final marginColor = summary.netProfit >= 0 ? UserTheme.statusSuccess : UserTheme.statusError;
    final marginLabel = '${summary.marginPercent.toStringAsFixed(1)}% Margin';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: UserUi.glassCard(
        context,
        blur: 16,
        padding: const EdgeInsets.all(20),
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : UserTheme.primaryOrange.withOpacity(0.15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: UserTheme.statusSuccess.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: UserTheme.statusSuccess,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "CRAFT BUSINESS FINANCIALS",
                          style: TextStyle(
                            color: UserTheme.statusSuccess,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Revenue & Net Profit",
                          style: TextStyle(
                            color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Margin Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: marginColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: marginColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    marginLabel,
                    style: TextStyle(
                      color: marginColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Revenue / Expense / Profit Metrics Row
            Row(
              children: [
                // Gross Revenue
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Gross Sales",
                        style: TextStyle(
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "₱${summary.grossRevenue.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: UserTheme.statusSuccess,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                // Total Expenses
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Expenses",
                        style: TextStyle(
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "₱${summary.totalExpenses.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: UserTheme.statusError,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                // Net Profit
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Net Profit",
                        style: TextStyle(
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "₱${summary.netProfit.toStringAsFixed(2)}",
                        style: TextStyle(
                          color: marginColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Ledger Action Button
            UserUi.premiumButton(
              label: 'OPEN FINANCIAL LEDGER & EXPENSES',
              onTap: onTapViewLedger ?? () {},
              icon: Icons.pie_chart_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
